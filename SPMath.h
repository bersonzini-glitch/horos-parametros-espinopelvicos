// Sagittal spinopelvic parameters from landmarks on a lateral standing radiograph.
// Pure C so it can be unit-tested outside Horos.
//
// Input points are image pixel coordinates (x to the right, y down), as Horos stores them.
// The facing direction is inferred from each endplate (anterior corner vs posterior corner),
// so the image can show the patient facing left or right.

#ifndef SPMATH_H
#define SPMATH_H

typedef struct { double x, y; int ok; } SPPoint;

typedef enum {
    SPFemoralHead1, SPFemoralHead2,
    SPS1Posterior, SPS1Anterior,      // S1 superior endplate
    SPL1Posterior, SPL1Anterior,      // L1 superior endplate
    SPT12Posterior, SPT12Anterior,    // T12 inferior endplate
    SPTKPosterior, SPTKAnterior,      // T4 (or T5) superior endplate
    SPT1Center, SPC7Center,
    SPLandmarkCount
} SPLandmark;

typedef struct {
    SPPoint p[SPLandmarkCount];
    double mmPerPixelX, mmPerPixelY;  // <= 0: uncalibrated (distances in pixels)
} SPInput;

typedef struct {
    double PI, PT, SS, LL, PILL, SVA, T1PA, TK;  // degrees; SVA in mm (or px)
    int hasPI, hasPT, hasSS, hasLL, hasPILL, hasSVA, hasT1PA, hasTK;
    int svaInMM;
} SPResult;

SPResult SPCompute(const SPInput *in);

// SRS-Schwab sagittal modifiers: "0", "+", "++" (NULL when the value is missing).
const char *SPSchwabPILL(const SPResult *r);
const char *SPSchwabPT(const SPResult *r);
const char *SPSchwabSVA(const SPResult *r);

#endif
