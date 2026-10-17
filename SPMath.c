#include "SPMath.h"
#include <math.h>

#define DEG (180.0 / M_PI)

// Patient frame: X positive anterior, Y positive up, in mm (or pixels when uncalibrated).
typedef struct { double X, Y; } V;

static V ToPatient(SPPoint p, double sx, double sy, double anterior) {
    return (V){ anterior * p.x * sx, -p.y * sy };
}

static double Wrap(double a) {
    while (a > 180) a -= 360;
    while (a <= -180) a += 360;
    return a;
}

// Inclination of an endplate (posterior corner -> anterior corner); positive when the
// anterior corner is higher.
static double Slope(V post, V ant) { return atan2(ant.Y - post.Y, ant.X - post.X) * DEG; }

// Angle of v from the upward vertical, positive towards anterior.
static double FromVertical(V v) { return atan2(v.X, v.Y) * DEG; }

SPResult SPCompute(const SPInput *in) {
    SPResult r = {0};
    const SPPoint *p = in->p;

    // Anterior direction in the image: first endplate available.
    double anterior = 0;
    static const SPLandmark pairs[][2] = {
        {SPS1Posterior, SPS1Anterior}, {SPL1Posterior, SPL1Anterior},
        {SPT12Posterior, SPT12Anterior}, {SPTKPosterior, SPTKAnterior},
    };
    for (int i = 0; i < 4 && !anterior; i++) {
        SPPoint a = p[pairs[i][1]], b = p[pairs[i][0]];
        if (a.ok && b.ok && a.x != b.x) anterior = a.x > b.x ? 1 : -1;
    }
    if (!anterior) return r;

    int calibrated = in->mmPerPixelX > 0 && in->mmPerPixelY > 0;
    double sx = calibrated ? in->mmPerPixelX : 1, sy = calibrated ? in->mmPerPixelY : 1;
#define P(l) ToPatient(p[l], sx, sy, anterior)
#define OK(l) (p[l].ok)

    int hasS1 = OK(SPS1Posterior) && OK(SPS1Anterior);
    int hasHip = OK(SPFemoralHead1) || OK(SPFemoralHead2);
    V hip = {0}, mid = {0};
    if (hasHip) {
        if (OK(SPFemoralHead1) && OK(SPFemoralHead2)) {
            V a = P(SPFemoralHead1), b = P(SPFemoralHead2);
            hip = (V){ (a.X + b.X) / 2, (a.Y + b.Y) / 2 };
        } else {
            hip = OK(SPFemoralHead1) ? P(SPFemoralHead1) : P(SPFemoralHead2);
        }
    }
    double s1Slope = 0;
    if (hasS1) {
        V a = P(SPS1Anterior), b = P(SPS1Posterior);
        mid = (V){ (a.X + b.X) / 2, (a.Y + b.Y) / 2 };
        s1Slope = Slope(b, a);
        r.SS = -s1Slope;
        r.hasSS = 1;
    }

    if (hasS1 && hasHip) {
        // PT: hip axis -> S1 midpoint vs vertical, positive when the hip axis is anterior.
        r.PT = FromVertical((V){ hip.X - mid.X, mid.Y - hip.Y });
        // PI: perpendicular to S1 at its midpoint vs line to the hip axis. Measured from the
        // downward vertical, the perpendicular sits at -SS and the hip line at +PT.
        r.PI = r.PT + r.SS;
        r.hasPT = r.hasPI = 1;
    }

    if (hasS1 && OK(SPL1Posterior) && OK(SPL1Anterior)) {
        r.LL = Wrap(Slope(P(SPL1Posterior), P(SPL1Anterior)) - s1Slope);
        r.hasLL = 1;
    }
    if (r.hasPI && r.hasLL) {
        r.PILL = r.PI - r.LL;
        r.hasPILL = 1;
    }

    if (OK(SPTKPosterior) && OK(SPTKAnterior) && OK(SPT12Posterior) && OK(SPT12Anterior)) {
        r.TK = Wrap(Slope(P(SPT12Posterior), P(SPT12Anterior)) - Slope(P(SPTKPosterior), P(SPTKAnterior)));
        r.hasTK = 1;
    }

    if (OK(SPC7Center) && OK(SPS1Posterior)) {
        r.SVA = P(SPC7Center).X - P(SPS1Posterior).X;
        r.hasSVA = 1;
        r.svaInMM = calibrated;
    }

    if (hasS1 && hasHip && OK(SPT1Center)) {
        V t1 = P(SPT1Center);
        r.T1PA = Wrap(FromVertical((V){ t1.X - hip.X, t1.Y - hip.Y }) - FromVertical((V){ mid.X - hip.X, mid.Y - hip.Y }));
        r.hasT1PA = 1;
    }
    return r;
}

static const char *Grade(double v, double lo, double hi) { return v < lo ? "0" : v <= hi ? "+" : "++"; }

const char *SPSchwabPILL(const SPResult *r) { return r->hasPILL ? Grade(r->PILL, 10, 20) : 0; }
const char *SPSchwabPT(const SPResult *r) { return r->hasPT ? Grade(r->PT, 20, 30) : 0; }
const char *SPSchwabSVA(const SPResult *r) { return r->hasSVA && r->svaInMM ? Grade(r->SVA, 40, 95) : 0; }
