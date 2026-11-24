# Erzeugt moon_de421.bin: geozentrischer Mond (ICRF, km) als Tschebyschow-Koeffizienten aus JPL DE421.
import numpy as np, de421, struct, sys
from jplephem.ephem import Ephemeris
e = Ephemeris(de421)
sets = e.load('moon')                     # (N, 3, 13), geozentrisch
N, axes, nc = sets.shape
dps = (e.jomega - e.jalpha) / N
start_jd = 2458849.5                      # 2020-01-01 00:00 TDB
i0 = int((start_jd - e.jalpha) // dps)
jd0 = e.jalpha + i0 * dps
end_jd = 2488069.5                        # 2100-01-01
i1 = int(np.ceil((end_jd - e.jalpha) / dps))
sub = np.ascontiguousarray(sets[i0:i1], dtype='<f8')
hdr = struct.pack('<4sIddII', b'MTX1', 1, jd0, dps, sub.shape[0], nc)
with open(sys.argv[1], 'wb') as f:
    f.write(hdr); f.write(sub.tobytes())
print('jalpha', e.jalpha, 'jomega', e.jomega, 'dps', dps, 'start', jd0, 'sets', sub.shape, 'bytes', len(hdr)+sub.nbytes)

# Selbsttest: eigene Auswertung (wie in Swift) gegen jplephem
def cheb(jd):
    k = int((jd - jd0) // dps); t = 2*((jd - jd0) - k*dps)/dps - 1
    c = sub[k]; T = np.ones(nc); T[1] = t
    for n in range(2, nc): T[n] = 2*t*T[n-1] - T[n-2]
    return c @ T
rng = np.random.default_rng(1)
err = 0
for jd in rng.uniform(jd0, jd0 + sub.shape[0]*dps - 1e-6, 5000):
    err = max(err, np.linalg.norm(cheb(jd) - e.position('moon', jd).ravel()))
print('max deviation own evaluator vs jplephem [km]:', err)
for jd in [2461368.5, 2461368.5 + 0.44167]:
    p = e.position('moon', jd).ravel(); print(jd, p, np.linalg.norm(p))
