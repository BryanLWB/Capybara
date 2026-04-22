package app.capybara.client

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Intent
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Shader
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.TextView
import kotlin.math.cos
import kotlin.math.sin
import app.capybara.client.R

class SplashActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var fluidAnimator: ValueAnimator? = null
    private var isFlutterReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_splash)

        // 全屏沉浸式
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_FULLSCREEN
        )
        window.statusBarColor = android.graphics.Color.BLACK
        window.navigationBarColor = android.graphics.Color.BLACK

        val logo = findViewById<TextView>(R.id.splash_logo_base)
        val sheenLogo = findViewById<TextView>(R.id.splash_logo_sheen)
        val glow1 = findViewById<View>(R.id.glow1)
        val glow2 = findViewById<View>(R.id.glow2)
        val glow3 = findViewById<View>(R.id.glow3)
        val density = resources.displayMetrics.density

        // 初始状态
        logo.alpha = 0f
        logo.scaleX = 0.95f
        logo.scaleY = 0.95f
        sheenLogo.alpha = 0f

        // === 流体光晕动画（无限循环） ===
        fluidAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 4000
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
            interpolator = LinearInterpolator()
            addUpdateListener { anim ->
                if (isFlutterReady) return@addUpdateListener
                
                val t = anim.animatedValue as Float
                val time = t * Math.PI * 4
                
                // 光晕动画
                glow1.alpha = 0.3f + 0.2f * sin(time).toFloat()
                glow1.translationX = (sin(time * 0.7) * 30 * density).toFloat()
                glow1.translationY = (cos(time * 0.5) * 20 * density).toFloat()
                glow1.scaleX = 1.0f + 0.1f * sin(time * 0.8).toFloat()
                glow1.scaleY = 1.0f + 0.1f * cos(time * 0.6).toFloat()
                
                glow2.alpha = 0.25f + 0.15f * cos(time + 1.0).toFloat()
                glow2.translationX = (cos(time * 0.6 + 2.0) * 40 * density).toFloat()
                glow2.translationY = (sin(time * 0.4 + 1.0) * 25 * density).toFloat()
                glow2.scaleX = 1.0f + 0.15f * cos(time * 0.9 + 0.5).toFloat()
                glow2.scaleY = 1.0f + 0.15f * sin(time * 0.7 + 0.5).toFloat()
                
                glow3.alpha = 0.2f + 0.1f * sin(time * 1.5 + 2.0).toFloat()
                glow3.translationX = (sin(time * 0.9 + 3.14) * 25 * density).toFloat()
                glow3.translationY = (cos(time * 0.7 + 1.57) * 30 * density).toFloat()
                glow3.scaleX = 1.0f + 0.2f * sin(time * 1.1 + 1.0).toFloat()
                glow3.scaleY = 1.0f + 0.2f * cos(time * 0.9 + 1.0).toFloat()
            }
        }

        // === 文字淡入 ===
        val logoFadeIn = AnimatorSet().apply {
            playTogether(
                ObjectAnimator.ofFloat(logo, View.ALPHA, 0f, 1f).apply {
                    duration = 1200
                    startDelay = 300
                },
                ObjectAnimator.ofFloat(logo, View.SCALE_X, 0.95f, 1f).apply {
                    duration = 1200
                    startDelay = 300
                },
                ObjectAnimator.ofFloat(logo, View.SCALE_Y, 0.95f, 1f).apply {
                    duration = 1200
                    startDelay = 300
                }
            )
        }

        // === 流光效果 ===
        val sheenAnim = buildSheenAnimator(sheenLogo)

        logo.post {
            // 立即启动 MainActivity（透明窗口，SplashActivity 仍可见）
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
            })
            
            // 启动动画（持续循环直到 Flutter 准备好）
            fluidAnimator?.start()
            logoFadeIn.start()
            sheenAnim.start()
        }
    }

    fun onFlutterReady() {
        isFlutterReady = true
        handler.post {
            fluidAnimator?.cancel()
            if (!isFinishing) {
                finish()
                overridePendingTransition(0, 0)
            }
        }
    }

    private fun buildSheenAnimator(logo: TextView): AnimatorSet {
        val width = logo.width.toFloat().coerceAtLeast(200f)
        
        val shimmer = LinearGradient(
            -width, 0f, 0f, 0f,
            intArrayOf(0x00FFFFFF, 0x40FFFFFF, 0xAAFFFFFF.toInt(), 0x40FFFFFF, 0x00FFFFFF),
            floatArrayOf(0f, 0.35f, 0.5f, 0.65f, 1f),
            Shader.TileMode.CLAMP
        )
        val matrix = Matrix()
        logo.paint.shader = shimmer
        logo.invalidate()

        val sweep = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 2000
            startDelay = 1000
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
            interpolator = LinearInterpolator()
            addUpdateListener { animator ->
                if (isFlutterReady) return@addUpdateListener
                val progress = animator.animatedValue as Float
                matrix.setTranslate(width * 3f * progress - width, 0f)
                shimmer.setLocalMatrix(matrix)
                logo.invalidate()
            }
        }

        val fade = ObjectAnimator.ofFloat(logo, View.ALPHA, 0f, 0.7f, 0.7f, 0f).apply {
            duration = 2000
            startDelay = 1000
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
        }

        return AnimatorSet().apply {
            playTogether(sweep, fade)
        }
    }

    override fun onDestroy() {
        fluidAnimator?.cancel()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
    
    companion object {
        @Volatile
        private var instance: SplashActivity? = null
        
        fun notifyFlutterReady() {
            instance?.onFlutterReady()
        }
    }
    
    override fun onResume() {
        super.onResume()
        instance = this
    }
    
    override fun onPause() {
        super.onPause()
        if (instance == this) {
            instance = null
        }
    }
}
