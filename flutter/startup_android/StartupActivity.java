package org.gestorherramientas.gestor_herramientas_quill_test;

import android.app.Activity;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

/** Draws the loader before creating any Flutter engine or loading Dart. */
public final class StartupActivity extends Activity {
    private boolean launched;
    private boolean frameScheduled;
    private final Runnable launchFallback = this::launchMainActivity;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!isTaskRoot() && Intent.ACTION_MAIN.equals(getIntent().getAction())
                && getIntent().hasCategory(Intent.CATEGORY_LAUNCHER)) {
            finish();
            return;
        }
        FrameLayout background = new FrameLayout(this);
        background.setBackgroundColor(Color.rgb(247, 249, 251));
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER);
        content.setPadding(dp(24), dp(24), dp(24), dp(24));
        ProgressBar progress = new ProgressBar(this);
        progress.setIndeterminate(true);
        progress.setIndeterminateTintList(ColorStateList.valueOf(Color.rgb(22, 139, 210)));
        progress.setContentDescription("Cargando la aplicación");
        content.addView(progress, new LinearLayout.LayoutParams(dp(42), dp(42)));
        addLabel(content, "Gestor de herramientas", 22, Color.rgb(32, 36, 42), 24, true);
        addLabel(content, "Cargando…", 14, Color.rgb(114, 119, 125), 12, false);
        background.addView(content, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER));
        setContentView(background);

        // Posting from onDraw lets this frame complete before MainActivity starts
        // initializing Flutter on the Android UI thread.
        final View decor = getWindow().getDecorView();
        decor.getViewTreeObserver().addOnDrawListener(new ViewTreeObserver.OnDrawListener() {
            @Override
            public void onDraw() {
                if (launched || frameScheduled) return;
                frameScheduled = true;
                final ViewTreeObserver.OnDrawListener listener = this;
                decor.post(() -> {
                    if (decor.getViewTreeObserver().isAlive()) {
                        decor.getViewTreeObserver().removeOnDrawListener(listener);
                    }
                    launchMainActivity();
                });
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Some older decor views do not dispatch this draw listener. Allow the
        // loader to render, then hand off without depending on that callback.
        getWindow().getDecorView().postDelayed(launchFallback, 600);
    }

    @Override
    protected void onPause() {
        getWindow().getDecorView().removeCallbacks(launchFallback);
        super.onPause();
    }

    private void launchMainActivity() {
        if (launched || isFinishing() || isDestroyed()) return;
        launched = true;
        getWindow().getDecorView().removeCallbacks(launchFallback);
        Intent intent = new Intent(this, MainActivity.class);
        if (getIntent().getExtras() != null) intent.putExtras(getIntent().getExtras());
        intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);
        startActivity(intent);
        finish();
        overridePendingTransition(0, 0);
    }

    private void addLabel(LinearLayout content, String text, int size, int color, int margin, boolean bold) {
        TextView label = new TextView(this);
        label.setText(text);
        label.setTextSize(size);
        label.setTextColor(color);
        label.setGravity(Gravity.CENTER);
        if (bold) label.setTypeface(label.getTypeface(), Typeface.BOLD);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.topMargin = dp(margin);
        content.addView(label, params);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
