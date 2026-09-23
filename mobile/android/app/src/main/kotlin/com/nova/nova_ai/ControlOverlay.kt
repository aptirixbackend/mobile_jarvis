package com.nova.nova_ai

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator

/**
 * The glowing border you see while Jarvis is driving the phone.
 *
 * This is a system overlay window, not a widget inside the app: the whole
 * point is that it stays visible while WhatsApp, Spotify or Settings are in
 * front. It never takes touches — FLAG_NOT_TOUCHABLE — so it cannot get in
 * the way of what is being automated.
 */
object ControlOverlay {

    private var view: GlowView? = null
    private var wm: WindowManager? = null

    fun canDraw(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    fun show(context: Context, label: String) {
        if (!canDraw(context)) return
        val manager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        view?.let { it.label = label; it.invalidate(); return }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        val glow = GlowView(context).also { it.label = label }
        try {
            manager.addView(glow, params)
            view = glow
            wm = manager
        } catch (e: Exception) {
            view = null
        }
    }

    fun update(label: String) {
        view?.let { it.label = label; it.postInvalidate() }
    }

    fun hide() {
        val v = view ?: return
        try {
            v.stop()
            wm?.removeView(v)
        } catch (e: Exception) {
            // already gone
        }
        view = null
    }

    /** Pulsing border drawn straight onto the canvas — no layout, no children. */
    private class GlowView(context: Context) : View(context) {

        var label: String = "Jarvis is working"

        private val density = resources.displayMetrics.density
        private val stroke = 5f * density
        private val radius = 34f * density
        private var phase = 0f

        private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            maskFilter = BlurMaskFilter(7f * density, BlurMaskFilter.Blur.NORMAL)
        }
        private val core = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.6f * density
            color = Color.argb(200, 130, 200, 255)
        }
        private val chipBg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(220, 12, 18, 32)
        }
        private val chipText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(235, 215, 235, 255)
            textSize = 12.5f * density
            textAlign = Paint.Align.CENTER
        }

        private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1800
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                phase = it.animatedValue as Float
                invalidate()
            }
            start()
        }

        fun stop() = animator.cancel()

        override fun onDetachedFromWindow() {
            animator.cancel()
            super.onDetachedFromWindow()
        }

        override fun onDraw(canvas: Canvas) {
            val inset = stroke / 2f
            val rect = RectF(inset, inset, width - inset, height - inset)

            // a cyan→violet sweep that travels around the edge
            val shift = (phase * 2f - 1f) * height
            border.shader = LinearGradient(
                0f, shift, width.toFloat(), shift + height,
                intArrayOf(
                    Color.argb(255, 0, 200, 255),
                    Color.argb(255, 120, 130, 255),
                    Color.argb(255, 180, 90, 255),
                    Color.argb(255, 0, 200, 255),
                ),
                floatArrayOf(0f, 0.35f, 0.7f, 1f),
                Shader.TileMode.MIRROR,
            )
            // breathe: 55% → 100% opacity
            border.alpha = (140 + 115 * kotlin.math.sin(phase * 2 * Math.PI).toFloat()
                .coerceAtLeast(-1f).let { (it + 1f) / 2f }).toInt().coerceIn(0, 255)

            canvas.drawRoundRect(rect, radius, radius, border)
            canvas.drawRoundRect(rect, radius, radius, core)

            // small caption at the top so it is obvious what is happening
            val text = label.take(46)
            val tw = chipText.measureText(text)
            val cx = width / 2f
            val top = 18f * density
            val chip = RectF(cx - tw / 2 - 14f * density, top,
                             cx + tw / 2 + 14f * density, top + 26f * density)
            canvas.drawRoundRect(chip, chip.height() / 2, chip.height() / 2, chipBg)
            canvas.drawText(text, cx, chip.centerY() + 4.5f * density, chipText)
        }
    }
}
