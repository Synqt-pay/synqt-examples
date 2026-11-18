package com.synqt.demo

import com.synqt.sdk.card.SynqtCard

/** The card variant adds CARD to the sheet, as a PCI DSS compliant merchant's app would when it starts. */
internal fun enableAddons() = SynqtCard.enable()
