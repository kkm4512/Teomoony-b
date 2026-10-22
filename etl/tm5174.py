import math
# EPSG:5174  +proj=tmerc +lat_0=38 +lon_0=127.002890277778 +k=1 +x_0=200000 +y_0=500000 +ellps=bessel +towgs84=-115.80,474.99,674.11,1.16,-2.31,-1.63,6.43
A_B, F_B = 6377397.155, 1/299.1528128
A_W, F_W = 6378137.0, 1/298.257223563
LAT0, LON0, K0, X0, Y0 = math.radians(38), math.radians(127.002890277778), 1.0, 200000.0, 500000.0
TW = (-115.80, 474.99, 674.11, 1.16, -2.31, -1.63, 6.43)
def _m(phi, a, e2):
    e4, e6 = e2*e2, e2*e2*e2
    return a*((1-e2/4-3*e4/64-5*e6/256)*phi-(3*e2/8+3*e4/32+45*e6/1024)*math.sin(2*phi)+(15*e4/256+45*e6/1024)*math.sin(4*phi)-(35*e6/3072)*math.sin(6*phi))
def tm_inv(x, y):
    a, f = A_B, F_B; e2 = f*(2-f); ep2 = e2/(1-e2)
    M = _m(LAT0, a, e2) + (y - Y0)/K0
    mu = M/(a*(1-e2/4-3*e2**2/64-5*e2**3/256))
    e1 = (1-math.sqrt(1-e2))/(1+math.sqrt(1-e2))
    p1 = mu+(3*e1/2-27*e1**3/32)*math.sin(2*mu)+(21*e1**2/16-55*e1**4/32)*math.sin(4*mu)+(151*e1**3/96)*math.sin(6*mu)+(1097*e1**4/512)*math.sin(8*mu)
    C1 = ep2*math.cos(p1)**2; T1 = math.tan(p1)**2; N1 = a/math.sqrt(1-e2*math.sin(p1)**2); R1 = a*(1-e2)/(1-e2*math.sin(p1)**2)**1.5
    D = (x-X0)/(N1*K0)
    lat = p1-(N1*math.tan(p1)/R1)*(D*D/2-(5+3*T1+10*C1-4*C1*C1-9*ep2)*D**4/24+(61+90*T1+298*C1+45*T1*T1-252*ep2-3*C1*C1)*D**6/720)
    lon = LON0+(D-(1+2*T1+C1)*D**3/6+(5-2*C1+28*T1-3*C1*C1+8*ep2+24*T1*T1)*D**5/120)/math.cos(p1)
    return lat, lon
def geo2xyz(lat, lon, a, f, h=0):
    e2 = f*(2-f); N = a/math.sqrt(1-e2*math.sin(lat)**2)
    return ((N+h)*math.cos(lat)*math.cos(lon), (N+h)*math.cos(lat)*math.sin(lon), (N*(1-e2)+h)*math.sin(lat))
def xyz2geo(X, Y, Z, a, f):
    e2 = f*(2-f); lon = math.atan2(Y, X); p = math.hypot(X, Y); lat = math.atan2(Z, p*(1-e2))
    for _ in range(8):
        N = a/math.sqrt(1-e2*math.sin(lat)**2); lat = math.atan2(Z+e2*N*math.sin(lat), p)
    return lat, lon
def to_wgs84(x, y):
    lat, lon = tm_inv(x, y)
    X, Y, Z = geo2xyz(lat, lon, A_B, F_B)
    dx, dy, dz, rx, ry, rz, s = TW
    rx, ry, rz = [math.radians(v/3600) for v in (rx, ry, rz)]; s = 1+s*1e-6
    # PROJ towgs84 = position vector (Bursa-Wolf)
    X2 = dx + s*(X - rz*Y + ry*Z); Y2 = dy + s*(rz*X + Y - rx*Z); Z2 = dz + s*(-ry*X + rx*Y + Z)
    la, lo = xyz2geo(X2, Y2, Z2, A_W, F_W)
    return math.degrees(lo), math.degrees(la)
