# 03 — Night mode DSP chain (`NightChain`)

**Od 2026-10-12 je strop brána (gate):** vstup se uvnitř řetězce vydělí vyhlazeným ceilingem, projde levelerem (jen stahuje, cíl −3 dB), kompresorem a limiterem na referenční úrovni 1.0 a na výstupu se ceilingem zase vynásobí. Signál pod stropem tak projde beze změny, signál nad stropem se stáhne na strop − 3 dB; špičky nikdy nad strop.

Soubory: `03-night-dsp.swift` (třída), `03-night-dsp-test.swift` (test harness).
Build a run testů:

```
swiftc -O 03-night-dsp.swift 03-night-dsp-test.swift -o nighttest && ./nighttest
```

## Co dělá

Vstup: součet všech tapovaných appek (mix bus Mixeru; Float32, stereo, 44.1/48 kHz, callbacky 64–4096 framů).
Řetězec, per sample, stereo-linked:

1. **Leveler (AGC)** — srovná různě hlasitá videa na jednu RMS úroveň těsně pod stropem; dolů jde rychle (0,15 s) a bez omezení, nahoru pomalu (3 s) a max o +12 dB.
2. **Kompresor 20:1** — loudness brickwall nad targetem: co leveler v prvních stovkách ms nestihne, srazí kompresor.
3. **Brickwall limiter s look-aheadem** — tvrdý strop na špičky, součet nikdy nepřesáhne ceiling.
4. **Ceiling** — výsledný multiplikátor; appka ho počítá z limitu „Maximální hlasitost" (dB) a aktuální hlasitosti výstupního zařízení, viz níže.

Výsledek (v3): krátkodobá hlasitost výstupu nikdy nepřekročí strop, ať je zdroj jakkoli hlasitý; zdroje tišší než strop − 12 dB zůstanou tišší (boost je omezený, aby se netahal šum).

Interně řetězec běží na referenční úrovni (ceiling = 1.0): target leveleru −3 dBFS RMS, threshold kompresoru −2 dBFS, limiter 0 dBFS, a ceiling se násobí až na konci. Protože všechny tři stupně jsou čistě gainové (homogenní), je to matematicky totéž jako „target = ceiling − 3 dB, threshold = ceiling − 2 dB, limiter = ceiling", ale:

- slider reaguje okamžitě (nečeká se na attack leveleru),
- stav leveleru/limiteru nezávisí na ceilingu, takže změna slideru nikdy nezpůsobí přestřelení: limiter drží ≤ 1.0 a násobí se ceilingem ≤ 1.0.

Ceiling je vyhlazený 5 ms one-pole filtrem (žádný zipper noise při tažení slideru) a výstup je navíc tvrdě oříznut na ±ceiling — to se uplatní jen pár ms po *snížení* ceilingu, kdy ve vyhlazovači ještě dobíhá stará vyšší hodnota.

## Parametry

| Stupeň | Parametr | Hodnota | Poznámka |
|---|---|---|---|
| Leveler | detektor | RMS (mean-square, one-pole) | integrace 300 ms, průměr L/R energie, bez K-weightingu |
| | target | ceiling − 3 dB RMS | tj. −3 dBFS RMS při ceilingu 1.0 |
| | attack (gain dolů) | τ = 0.15 s | one-pole v dB doméně |
| | release (gain nahoru) | τ = 3.0 s | one-pole v dB doméně |
| | max boost / max cut | 0 dB (jen stahuje, od 2026-10-12) / −60 dB | cut prakticky neomezený (sanitizace vstupu končí na +36 dBFS) |
| | silence gate | RMS < −55 dBFS → gain se drží | žádné vytahování šumu v tichu |
| Kompresor | threshold | ceiling − 2 dB (peak) | |
| | ratio | 20:1 | loudness brickwall nad targetem |
| | knee | 6 dB soft | kvadratická (Giannoulis) |
| | attack / release | 3 ms / 200 ms | branching one-pole v dB doméně na gain reduction |
| | detektor | peak, max(|L|,|R|) | stereo-linked, bez makeup gainu |
| Limiter | look-ahead | 5 ms | sliding-window min požadovaného gainu → box average → lineární rampa dolů, gain dosáhne hodnoty přesně v okamžiku špičky |
| | ceiling | 1.0 interně × ceiling na výstupu | |
| | release | τ = 80 ms | one-pole v lineární doméně |
| | detektor | peak, max(|L|,|R|) | stereo-linked |
| Ceiling | smoothing | 5 ms one-pole | + hard clamp na ±ceiling |
| Sanitizace | vstup | NaN → 0, ±inf a |x| > 64 → ±64 | ceiling: NaN/záporný → 0, > 1 → 1 |

Uvedené hodnoty jsou `public static let` konstanty na třídě; změna vyžaduje překompilování (záměrně, žádné mutable parametry do RT vlákna).

## Latence

Jediný zdroj latence je look-ahead limiteru (`latencySamples`): `round(0.005 × sampleRate)`.

| Sample rate | Latence | ms |
|---|---|---|
| 44.1 kHz | 221 samplů | 5.01 ms |
| 48 kHz | 240 samplů | 5.00 ms |

Leveler a kompresor jsou feed-forward bez zpoždění. Pro synchronizaci s obrazem je 5 ms nepodstatné (audio z tapu se navíc přehrává přes vlastní výstup s vlastní bufferizací), takže žádná kompenzace není potřeba.

## Mapování „Maximální hlasitost" na ceiling (v2)

Limit v menu je přímo v dB (slider −60…0 dB, celé kroky) a je globální pro součet všech appek. Appka počítá ceiling s ohledem na systémovou hlasitost výstupního zařízení (`kAudioDevicePropertyVolumeDecibels`, scope output, element 0; fallbacky: element 1, `VolumeScalar` převedený přes `VolumeScalarToDecibels` nebo 20·log10, jinak 0 dB):

```
ceiling = min(1, 10^((capDB − outputVolumeDB) / 20))
```

Tj. při hlasitosti výstupu −20 dB a limitu −30 dB dostane chain ceiling −10 dBFS; při hlasitosti −40 dB je ceiling 1.0 (limit není dosažitelný, chain jen srovnává). Ceiling se přepočítá při každé změně hlasitosti (listener na `VolumeScalar`), posunu slideru nebo přepnutí nočního režimu, bez přestavby busu.

Target leveleru se odvozuje automaticky: `targetRMS = ceiling − 3 dB`. Aplikace nic dalšího nenastavuje — do `process()` posílá jen `ceiling`.

Od v3 je strop míněn jako **hard loudness cap**: slider „Maximální hlasitost" říká, jak hlasitý smí výstup krátkodobě (300 ms RMS) být, ne jen kam smí sahat špičky. Leveler proto míří na strop − 3 dB, kompresor 20:1 s thresholdem strop − 2 dB drží všechno nad tím na místě a limiter chytá zbylé špičky. Cena: obsah s velkým crest factorem je pod stropem silně komprimovaný (špičky dialogu i výbuchy sedí na stropu); pro noční poslech je to záměr. Dřívější v2 (target −10 dB, 6:1) nechávala hlasitost kolísat podle zdroje a strop platil jen pro špičky.

## Integrace

**Vlákna.** `process()`/`processInterleaved()` jsou určeny výhradně pro RT vlákno tapu/IO procu: nealokují, nezamykají, nevolají ObjC, nepoužívají Swift Array, veškerý stav je per-sample (výstup je bitově shodný pro libovolné velikosti callbacku — viz test (e)). `init`, `reconfigure`, `reset` alokují/mažou buffery a **nesmí** běžet zároveň s `process()`.

**Ceiling.** Předávej aktuální hodnotu slideru každý callback (např. z `atomic`/`OSAllocatedUnfairLock`-free `UnsafeAtomic<Float>` nebo prostě z `Float` proměnné — čtení Floatu je na arm64 atomické, jen se vyhni struct s více poli). Vyhlazování je uvnitř.

**Kdy volat `reset()`.** Při zapnutí nočního režimu (přechod bypass → chain) a po delší pauze audia (např. po resume tapu). Reset vynuluje delay line a nastaví gain na 0 dB — první zpracovaný blok tedy začne 5 ms tichem (prázdný delay line) a leveler startuje z 0 dB; při přepnutí uprostřed hlasitého přehrávání to udělá slyšitelné „cvaknutí"/skok, což je pro on/off toggle akceptovatelné. Kdo chce přechod bez cvaknutí: v aplikaci crossfade 20–50 ms mezi bypass a výstupem chainu (chain pusť na ~10 ms dřív, ať se naplní delay line).

**Kdy volat `prime(levelerGainDB:compressorGainDB:)`.** Při make-before-break přestavbě mix busu (nová instance chainu nahrazuje běžící): před spuštěním nového IO procu předej gain leveleru a kompresoru ze staré instance (metery `levelerGainDB`/`compressorGainDB`, v appce snapshotované do `Atomic<Float>`). Nový chain pak pokračuje na stejné úrovni místo skoku na 0 dB a několikasekundového náběhu (release 3 s). `prime` nastaví jen gain leveleru (oříznutý na −60…+12 dB), gain reduction kompresoru (≤ 0) a mean-square tak, aby cílový gain leveleru odpovídal seedu (žádný gate, žádný drift); delay line, limiter a ceiling smoothing zůstávají po `reset()`. Volat mimo RT vlákno, před prvním `process()`. Neseeduj po toggle nočního režimu ani ze stavu chainu, který ještě fadeuje — viz test (g).

**Kdy volat `reconfigure(sampleRate:maxFrames:)`.** Při změně sample rate výstupního/tap zařízení nebo maxima framů v callbacku. Postup: zastav tap / IO proc (nebo přepni na bypass a počkej na dokončení běžícího callbacku), zavolej `reconfigure`, spusť znovu. Alternativa bez zastavování: vytvoř novou instanci `NightChain` s novými parametry a atomicky prohoď referenci, kterou RT vlákno používá (starou nech uvolnit až po dalším callbacku). `reconfigure` sám volá `reset()`.

**Změna sample rate.** Coeficienty (všechny časové konstanty) i délka look-aheadu se přepočítávají z `sampleRate`, takže chain funguje pro libovolný rate ≥ 8 kHz; nepodporovaný/NaN rate spadne na 48 kHz. Nikdy nepouštěj `process()` s jiným sample rate, než na jaký je chain nakonfigurovaný — vyhlazování by mělo špatné časy a look-ahead špatnou délku (limiter by pořád držel strop, jen s jinou latencí).

**`maxFrames`** omezuje jen scratch buffery pro `processInterleaved` (delší bloky se zpracují po kusech, výsledek je stejný); `process(left:right:)` přijme libovolný počet framů.

**Meters** (`levelerGainDB`, `compressorGainDB`, `limiterGainDB`) se aktualizují jednou za blok; čtení z UI vlákna je datový race na plain Floatu — pro zobrazení v menubaru neškodné, pro cokoli jiného ne.

## Výsledky testů (finální běh v3, `swiftc -O`, M1 Pro)

```
PASS  (a) 0 dBFS sine, ceiling 0.25  max |out| = 0.248209
PASS  (a) 0 dBFS sine, ceiling 0.5  max |out| = 0.496417
PASS  (a) 0 dBFS sine, ceiling 1.0  max |out| = 0.992835
PASS  (a+) +12 dBFS noise/square, ceiling 0.1  max |out| = 0.100000
PASS  (a+) +12 dBFS noise/square, ceiling 0.5  max |out| = 0.500000
PASS  (a+) +12 dBFS noise/square, ceiling 1.0  max |out| = 1.000000
PASS  (b) -35 dBFS: gain at 6 s >= +9 dB  gain = +10.37 dB
PASS  (b) -35 dBFS: steady RMS within 3 dB of target  out RMS -26.62 dBFS, reachable target -26.01 dBFS (ideal -3 dBFS, input RMS -38.01 dBFS, boost capped at +12)
PASS  (c) step: no sample exceeds ceiling  max |out| = 1.000000
PASS  (c) step: leveler gain within 1 dB of target after 8 s  gain at step +9.73 dB -> +3.01 dB (target +3.01 dB)
PASS  (d) silence in -> silence out (fresh)  max |out| = 0
PASS  (d) silence after loud content (past latency)  max |out| after latency = 0
PASS  (d) NaN/inf input -> finite output  max |out| = 1.000000
PASS  (e) block 64 vs 4096  max diff = 0
PASS  (e) block 512 vs 4096  max diff = 0
PASS  (e) block 1000 vs 4096  max diff = 0
PASS  (e) block 4096 vs 4096  max diff = 0
PASS  (e) interleaved, chunked (maxFrames 1024, frames 4096) vs reference  max diff = 0
PASS  (g) prime: seeded gain is the leveler's steady gain  seeded gain +11.57 dB
PASS  (g) prime: primed chain continues within 1 dB of the running chain  running -32.46 dBFS, primed -32.46 dBFS, unprimed -43.86 dBFS (first 100 ms after latency)
PASS  (g) prime: unprimed chain would jump by more than 6 dB  jump 11.41 dB
PASS  (g) prime: primed chain stays put over 0.5 s  running -32.40 dBFS, primed -32.40 dBFS (last 100 ms)
PASS  (g) prime: never exceeds ceiling  max |out| = 0.033935
PASS  (h) +30 / -3 / -11 dBFS settle within 1.5 dB of each other  RMS +30: -10.83, -3: -10.85, -11: -10.91 dBFS (spread 0.08 dB), leveler gains -30.0 / +3.0 / +10.8 dB
PASS  (h) all three stay at or under the cap  cap -6.02 dBFS, max |out| = 0.500000
PASS  (h) +30 dBFS is pulled down within 2 s (cut beyond the old -24 dB limit)  RMS at 1-2 s -10.82 dBFS vs final -10.83 dBFS, leveler gain -30.0 dB
PASS  (h) -23 dBFS cannot reach the -3 dBFS target (needs +23 dB, boost limit +12 dB) so the spec's -3 vs -23 equality is not testable; also 3 s is too short for release tau = 3 s, measured over 10-12 s; must hit the +12 dB limit and stay under the cap  leveler gain +11.78 dB, RMS -20.35 dBFS (input -26.01 dBFS + 12 dB + ceiling)
PASS  (f) 10 s stereo 48 kHz in 512-frame blocks  21.1 ms (0.21% of real time)
latency: 221 samples @ 44.1 kHz, 240 samples @ 48 kHz
ALL TESTS PASSED
```

Poznámky k testům:

- (b) −35 dBFS sinus má RMS −38 dBFS; na target −3 dBFS by bylo potřeba +35 dB, boost je ale omezen na +12 dB, takže dosažitelný target je −26 dBFS. Test porovnává proti tomuto dosažitelnému targetu. Gain +10.37 dB v 6 s odpovídá přesně τ = 3 s: 12 × (1 − e^(−6/3)).
- (a+) je nad rámec zadání: šum a obdélník na +12 dBFS (vstup 4.0) střídané po 100 ms, callback 64 framů. Ověřeno i s vypnutým finálním clampem — limiter sám drží strop, clamp je jen pojistka pro přechody ceilingu.
- (g) chain A běží 10 s na −35 dBFS (leveler na +11.6 dB), chain B se seedne přes `prime` z A a oba dostanou dalších 0.5 s stejného signálu: primed B je do 0.01 dB od A hned po latenci, neseedovaný chain C by začal o 11.4 dB tišeji (to je skok, který byl slyšet při každé přestavbě busu).
- Kompresor se u testu (c) nedostane do hry na dlouho: limiter pokryje prvních ~5 ms po skoku, kompresor dalších ~0.3 s, než leveler (attack 0.15 s) stáhne gain z +9.7 na +3 dB.
- (h) je test hard loudness capu (v3): stejný sinus na +30 / −3 / −11 dBFS skončí po 12 s na stejné RMS s rozptylem 0.08 dB a pod stropem (ceiling 0.5 → cap −6 dBFS, výstup −10.8 dBFS = target −3 dB, kompresor −2 dB, ceiling −6 dB). +30 dBFS vyžaduje cut −33 dB (za starým limitem −24 dB) a sedí na místě už v 1–2 s. Zadání chtělo porovnat −3 a −23 dBFS, ale −23 dBFS sinus (RMS −26) by potřeboval +23 dB a boost je omezený na +12 dB, takže na target nedosáhne — test to měří zvlášť a ověřuje, že skončí přesně na +12 dB a pod stropem. Měří se posledních 2 s z 12 s, protože release τ = 3 s se po 3 s ještě neusadí.

## Známá omezení

- **RMS není loudness.** Bez K-weightingu měří basy stejně jako hlas; basově těžká hudba se tedy může jevit jako „stejně hlasitá", ale zní tišeji než dialog na stejné RMS. Kdyby to v praxi vadilo: přidat K-weighting (high-shelf +4 dB nad 1.5 kHz + high-pass 60 Hz) před detektor leveleru — dva biquady, nic víc.
- **Sample-peak, ne true-peak.** Limiter drží sample peak ≤ ceiling; po rekonstrukci v DAC mohou inter-sample špičky přesáhnout o ~0.3 dB. Při ceilingu 1.0 (100 %) to může na výstupu zařízení jemně clipnout; pokud bude vadit, mapuj 100 % na 0.95 (−0.45 dB).
- **Klik při zapnutí** (viz `reset()`), řeší se crossfadem v appce.
- **Ceiling je globální (od v2).** Mixer má jeden mix bus (jeden aggregate, jeden tap na každou hrající appku), appky sečte před `NightChain`, takže strop platí pro součet. Netapovaný systémový zvuk (procesy bez tapu, systémové zvuky) strop pořád obchází.
- **Jen stereo.** Mono tap je třeba rozkopírovat do L/R (nebo volat `process` se stejným pointerem pro left i right — funguje, stav je stereo-linked, jen se dvakrát násobí totéž).
- **Gate bez hystereze.** Kolem −55 dBFS RMS může gain lehce „ťukat" mezi hold a pohybem; při τ 0.15/3 s to není slyšet.
- **Leveler je rychlý (v3).** Náhlý přechod z tiché scény na hlasitou (reklama, výbuch) prvních ~0.15 s pokrývá kompresor 20:1 + limiter, pak leveler; hlasitost je tvrdě omezena stropem. Attack 0.15 s a kompresor 20:1 na dynamické hudbě slyšitelně pumpují a zplošťují dynamiku — pro noční poslech záměr, pro hudbu nevhodné.
- **Změna ceilingu dolů** je ~5 ms hard-clipována (vyhlazený ceiling dobíhá), při tažení slideru neslyšitelné.
- `reconfigure`/`reset` nejsou thread-safe vůči `process()` — odpovědnost aplikace (viz Integrace).
