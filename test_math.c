// Synthetic geometry with known answers, rendered facing right and facing left.
#include "SPMath.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
static void Check(const char *name, int has, double got, double want) {
    int ok = has && fabs(got - want) < 0.01;
    if (!ok) failures++;
    printf("  %-5s %8.2f  (esperado %8.2f) %s\n", name, has ? got : NAN, want, ok ? "ok" : "FALLA");
}

static void Endplate(SPInput *in, SPLandmark post, SPLandmark ant, double cx, double cy, double slopeDeg, double a, double sx, double sy) {
    double t = slopeDeg * M_PI / 180, h = 20;
    double X[2] = {cx - h * cos(t), cx + h * cos(t)}, Y[2] = {cy - h * sin(t), cy + h * sin(t)};
    in->p[post] = (SPPoint){500 + X[0] / (a * sx), 2000 - Y[0] / sy, 1};
    in->p[ant] = (SPPoint){500 + X[1] / (a * sx), 2000 - Y[1] / sy, 1};
}

static void Run(double a) {
    double sx = 0.5, sy = 0.5;
    SPInput in = {.mmPerPixelX = sx, .mmPerPixelY = sy};
#define PT_(l, X, Y) in.p[l] = (SPPoint){500 + (X) / (a * sx), 2000 - (Y) / sy, 1}
    PT_(SPFemoralHead1, 2, 1);
    PT_(SPFemoralHead2, -2, -1);
    Endplate(&in, SPS1Posterior, SPS1Anterior, -20, 100, -40, a, sx, sy);
    Endplate(&in, SPL1Posterior, SPL1Anterior, -30, 300, 15, a, sx, sy);
    Endplate(&in, SPT12Posterior, SPT12Anterior, -20, 380, 10, a, sx, sy);
    Endplate(&in, SPTKPosterior, SPTKAnterior, 0, 520, -30, a, sx, sy);
    PT_(SPT1Center, 30, 600);
    PT_(SPC7Center, 0, 620);

    SPResult r = SPCompute(&in);
    double pt = atan2(20, 100) * 180 / M_PI;
    printf("Paciente mirando a la %s:\n", a > 0 ? "derecha" : "izquierda");
    Check("PI", r.hasPI, r.PI, pt + 40);
    Check("PT", r.hasPT, r.PT, pt);
    Check("SS", r.hasSS, r.SS, 40);
    Check("LL", r.hasLL, r.LL, 55);
    Check("PI-LL", r.hasPILL, r.PILL, pt + 40 - 55);
    Check("TK", r.hasTK, r.TK, 40);
    Check("SVA", r.hasSVA && r.svaInMM, r.SVA, 20 + 20 * cos(40 * M_PI / 180));
    Check("T1PA", r.hasT1PA, r.T1PA, atan2(30, 600) * 180 / M_PI + pt);
    printf("  Schwab PI-LL %s  PT %s  SVA %s\n", SPSchwabPILL(&r), SPSchwabPT(&r), SPSchwabSVA(&r));
}

int main(void) {
    Run(1);
    Run(-1);
    printf(failures ? "\n%d FALLAS\n" : "\nTodo ok\n", failures);
    return failures != 0;
}
