package com.coucou.android.core

/**
 * The design tokens as plain numbers, so a test can check contrast and the scale without Compose. The app is dark only.
 *
 * Louis Raillé's Mochi, its state colours and the pill colours are not here and are not changed.
 */
data class Tokens(
    /** The screen. */
    val bg: Long,
    /** Island panels and cards. */
    val panel: Long,
    /** Rows inside a panel, chips, the selected tab. */
    val panel2: Long,
    /** The thin border of a panel. */
    val line: Long,
    val text: Long,
    val textDim: Long,
    /** Hints and placeholders: large text and icons only. */
    val textFaint: Long,
    /** The one main action: a pill, as on the PC. */
    val primaryButton: Long, val onPrimaryButton: Long,
    /** Every other pill, as a solid colour on [panel]. */
    val secondaryButton: Long,
    val danger: Long,
    /** The "connected" dot and the on switch. */
    val online: Long,
    /** Alpha of the coloured glow at the bottom of a panel (0..1). */
    val washAlpha: Double,
) {
    companion object {
        val DARK = Tokens(
            bg = 0xFF0B0B0D, panel = 0xFF15171B, panel2 = 0xFF202329, line = 0xFF30343C,
            text = 0xFFF4F4F6, textDim = 0xFFC8C8D0, textFaint = 0xFF9696A0,
            primaryButton = 0xFF34D399, onPrimaryButton = 0xFF04150C, secondaryButton = 0xFF252830,
            danger = 0xFFFF8A75, online = 0xFF34D399, washAlpha = 0.32,
        )
    }
}

/** The obsidian surfaces: the hero panel on Home, sheets, and the island over other apps. */
object IslandSurface {
    const val BLACK = 0xFF000000L
    const val PANEL = 0xFF15171BL
    const val HERO = 0xFF131316L
    const val LINE = 0xFF2E3138L
    const val TEXT = 0xFFF4F4F6L
    const val TEXT_DIM = 0xFFC8C8D0L
    /** Pill buttons on these always-dark surfaces. */
    const val PRIMARY = 0xFF34D399L
    const val BUTTON = 0xFF252830L
    const val ON_PRIMARY = 0xFF04150CL
}

/**
 * Status and link dot colours (Pace tones): each is visible (3:1 or better) on black and on the dark panels.
 */
object StatusPalette {
    const val WORKING = 0xFF3E8BFFL
    const val THINKING = 0xFFA77CFFL
    const val ATTENTION = 0xFFFFB020L
    const val DONE = 0xFF34D399L
    const val ERROR = 0xFFFF6A4DL
    const val IDLE = 0xFF9696A0L

    const val ONLINE = DONE
    const val BUSY = ATTENTION
    const val OFFLINE = IDLE
}

/** The spacing scale (dp): every gap, padding and gutter is one of these. */
object Spacing {
    val SCALE = listOf(4, 8, 12, 16, 24, 32)
    const val GUTTER = 16
    const val GAP = 12
    const val INSIDE = 16
    /** The smallest thing a finger must be able to hit, in dp. */
    const val MIN_TOUCH = 48
}

/** Corner radii (dp). Pills and chips are fully round. */
object Radii {
    const val PANEL = 20
    const val SHEET = 28
    const val ISLAND_EXPANDED = 22
    const val ISLAND_COMPACT = 14
    const val HERO_BOTTOM = 30
}

/** One step of the type scale: sizes are sp, so the user's font size setting applies. */
data class TypeStep(val name: String, val sizeSp: Int, val lineSp: Int, val weight: Int)

object TypeScale {
    val DISPLAY = TypeStep("display", 28, 34, 700)
    val TITLE = TypeStep("title", 20, 26, 700)
    val HEADLINE = TypeStep("headline", 16, 22, 600)
    val BODY = TypeStep("body", 15, 22, 400)
    val SECONDARY = TypeStep("secondary", 13, 18, 400)
    val LABEL = TypeStep("label", 12, 16, 600)
    /** Only for the exact command and code in chat. */
    val MONO = TypeStep("mono", 12, 18, 400)
    val ALL = listOf(DISPLAY, TITLE, HEADLINE, BODY, SECONDARY, LABEL, MONO)
}

/** Motion constants shared with the PC (see core/IslandMotion.kt for the springs). */
object MotionSpec {
    const val RETRACT_MS = 340
    /** With "remove animations" on, a spring or a slide becomes this fade. */
    const val REDUCED_MS = 120

    /** Android's "Remove animations" (and developer "animator duration scale: off") sets the scale to 0. */
    fun isReduced(animatorDurationScale: Float): Boolean = animatorDurationScale <= 0f
}
