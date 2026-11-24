# Erzeugt moon_de440.bin: geozentrischer Mond (ICRF, km) als Tschebyschow-Koeffizienten aus JPL DE440.
#
# Quelle: de440s.bsp (DE440, Kurzfassung 1849–2150) von JPL/NAIF:
#   https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp
# Aufruf: python3 Tools/make_ephem.py /pfad/zu/de440s.bsp Shared/moon_de440.bin
# Benötigt: pip install jplephem numpy
#
# Das SPK enthält Mond (301) und Erde (399) jeweils relativ zum Erde-Mond-Schwerpunkt (3),
# mit identischen 4-Tage-Intervallen. Der geozentrische Mond ist die Differenz der Koeffizienten.
import numpy as np, struct, sys
from jplephem.spk import SPK

kernel = SPK.open(sys.argv[1])
seg_moon, seg_earth = kernel[3, 301], kernel[3, 399]
init_m, dps_m, c_moon = seg_moon.load_array()      # Koeffizienten: (3, N, nc), Zeiten in JD (TDB) bzw. Tagen
init_e, dps_e, c_earth = seg_earth.load_array()
assert init_m == init_e and dps_m == dps_e and c_moon.shape == c_earth.shape, 'Intervalle von 301 und 399 passen nicht'
init, dps = init_m, dps_m
sets = np.transpose(c_moon - c_earth, (1, 0, 2))    # (N, 3, nc), geozentrisch
N, axes, nc = sets.shape

start_jd = 2458849.5                      # 2020-01-01 00:00 TDB
i0 = int((start_jd - init) // dps)
jd0 = init + i0 * dps
end_jd = 2488069.5                        # 2100-01-01
i1 = int(np.ceil((end_jd - init) / dps))
sub = np.ascontiguousarray(sets[i0:i1], dtype='<f8')
hdr = struct.pack('<4sIddII', b'MTX1', 1, jd0, dps, sub.shape[0], nc)
with open(sys.argv[2], 'wb') as f:
    f.write(hdr); f.write(sub.tobytes())
print('DE440: init', init, 'dps', dps, 'start', jd0, 'sets', sub.shape, 'bytes', len(hdr) + sub.nbytes)

# Selbsttest: eigene Auswertung (wie in Swift) gegen jplephem
def moon_geo(jd):
    return (seg_moon.compute(jd) - seg_earth.compute(jd)).ravel()

def cheb(jd):
    k = int((jd - jd0) // dps); t = 2*((jd - jd0) - k*dps)/dps - 1
    c = sub[k]; T = np.ones(nc); T[1] = t
    for n in range(2, nc): T[n] = 2*t*T[n-1] - T[n-2]
    return c @ T
rng = np.random.default_rng(1)
err = 0
for jd in rng.uniform(jd0, jd0 + sub.shape[0]*dps - 1e-6, 5000):
    err = max(err, np.linalg.norm(cheb(jd) - moon_geo(jd)))
print('max deviation own evaluator vs jplephem [km]:', err)
for jd in [2461368.5, 2461368.5 + 0.44167]:
    p = moon_geo(jd); print(jd, p, np.linalg.norm(p))
