'use client';

import { useEffect, useRef, useState } from 'react';
import styles from './PingPongAnimation.module.css';

type Game = {
  width: number; height: number; playerY: number; autoY: number;
  ballX: number; ballY: number; vx: number; vy: number;
  serveAt: number; rally: number; playerScore: number; autoScore: number;
};

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
const freshGame = (): Game => ({
  width: 0, height: 0, playerY: 0, autoY: 0, ballX: 0, ballY: 0,
  vx: 0, vy: 0, serveAt: 0, rally: 0, playerScore: 0, autoScore: 0,
});

function serve(game: Game, direction: 1 | -1, delay = 0) {
  game.ballX = game.width / 2;
  game.ballY = game.height * (0.36 + Math.random() * 0.28);
  game.vx = direction * game.width * 0.56;
  game.vy = (Math.random() - 0.5) * game.height * 0.44;
  game.serveAt = performance.now() + delay;
  game.rally = 0;
}

function paintPaddle(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, player: boolean) {
  const faceWidth = width * 1.35;
  const faceHeight = height * 0.92;
  const gripX = player ? x - faceWidth / 2 - width * 1.05 : x + faceWidth / 2;
  ctx.fillStyle = '#0F172A';
  ctx.beginPath();
  ctx.roundRect(gripX, y - width * 0.3, width * 1.05, width * 0.6, width * 0.18);
  ctx.fill();
  ctx.strokeStyle = 'rgba(255, 255, 255, .35)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(gripX + width * 0.28, y - width * 0.25);
  ctx.lineTo(gripX + width * 0.28, y + width * 0.25);
  ctx.stroke();

  const gradient = ctx.createLinearGradient(x - faceWidth / 2, y, x + faceWidth / 2, y);
  gradient.addColorStop(0, player ? '#1D4ED8' : '#C2410C');
  gradient.addColorStop(0.5, player ? '#60A5FA' : '#FDBA74');
  gradient.addColorStop(1, player ? '#2563EB' : '#F97316');
  ctx.save();
  ctx.shadowColor = player ? 'rgba(37, 99, 235, .55)' : 'rgba(249, 115, 22, .45)';
  ctx.shadowBlur = 18;
  ctx.shadowOffsetY = 5;
  ctx.fillStyle = gradient;
  ctx.beginPath();
  ctx.ellipse(x, y, faceWidth / 2, faceHeight / 2, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = 'rgba(255, 255, 255, .55)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.ellipse(x, y, faceWidth / 2 - 2, faceHeight / 2 - 2, 0, 0, Math.PI * 2);
  ctx.stroke();
  ctx.fillStyle = 'rgba(255, 255, 255, .32)';
  ctx.fillRect(x - 1, y - faceHeight * 0.27, 2, faceHeight * 0.54);
}

function paint(ctx: CanvasRenderingContext2D, game: Game, reducedMotion: boolean) {
  const { width, height } = game;
  const inset = Math.max(12, width * 0.025);
  const paddleWidth = clamp(width * 0.035, 12, 18);
  const paddleX = inset + paddleWidth * 1.15;
  const ballRadius = clamp(width * 0.017, 6, 9);
  ctx.clearRect(0, 0, width, height);
  const surface = ctx.createLinearGradient(0, 0, width, height);
  surface.addColorStop(0, '#102448');
  surface.addColorStop(0.55, '#17376A');
  surface.addColorStop(1, '#0B1D3C');
  ctx.fillStyle = surface;
  ctx.fillRect(0, 0, width, height);
  ctx.fillStyle = 'rgba(96, 165, 250, .055)';
  ctx.fillRect(inset, inset, width / 2 - inset, height - inset * 2);
  ctx.strokeStyle = 'rgba(191, 219, 254, .43)';
  ctx.lineWidth = 2;
  ctx.strokeRect(inset, inset, width - inset * 2, height - inset * 2);
  ctx.setLineDash([5, 8]);
  ctx.beginPath();
  ctx.moveTo(width / 2, inset);
  ctx.lineTo(width / 2, height - inset);
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.strokeStyle = 'rgba(191, 219, 254, .2)';
  ctx.beginPath();
  ctx.arc(width / 2, height / 2, height * 0.14, 0, Math.PI * 2);
  ctx.stroke();
  paintPaddle(ctx, paddleX, game.playerY, paddleWidth, height * 0.22, true);
  paintPaddle(ctx, width - paddleX, game.autoY, paddleWidth, height * 0.22, false);
  if (!reducedMotion && game.vx) {
    ctx.strokeStyle = 'rgba(251, 146, 60, .2)';
    ctx.lineWidth = ballRadius * 1.5;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(game.ballX - game.vx * 0.045, game.ballY - game.vy * 0.045);
    ctx.lineTo(game.ballX, game.ballY);
    ctx.stroke();
  }
  ctx.save();
  ctx.shadowColor = '#FB923C';
  ctx.shadowBlur = 16;
  ctx.fillStyle = '#FFF7ED';
  ctx.beginPath();
  ctx.arc(game.ballX, game.ballY, ballRadius, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = '#F97316';
  ctx.lineWidth = 2.5;
  ctx.stroke();
}

export default function PingPongAnimation() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const gameRef = useRef<Game>(freshGame());
  const draggingRef = useRef(false);
  const [score, setScore] = useState({ player: 0, auto: 0 });
  const [rally, setRally] = useState(0);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;
    const game = gameRef.current;
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    let frame = 0;
    let previous = performance.now();
    let visible = true;

    const resize = () => {
      const bounds = canvas.getBoundingClientRect();
      if (!bounds.width || !bounds.height) return;
      const oldHeight = game.height;
      game.width = bounds.width;
      game.height = bounds.height;
      game.playerY = oldHeight ? game.playerY / oldHeight * game.height : game.height / 2;
      game.autoY = oldHeight ? game.autoY / oldHeight * game.height : game.height / 2;
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.round(bounds.width * ratio);
      canvas.height = Math.round(bounds.height * ratio);
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      serve(game, -1, 500);
      paint(ctx, game, reducedMotion);
    };
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    const visibilityObserver = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; });
    visibilityObserver.observe(canvas);

    const animate = (time: number) => {
      const dt = Math.min((time - previous) / 1000, 0.035);
      previous = time;
      if (visible && document.visibilityState === 'visible' && game.width && game.height) {
        const halfPaddle = game.height * 0.11;
        const paddleWidth = clamp(game.width * 0.035, 12, 18);
        const paddleX = Math.max(12, game.width * 0.025) + paddleWidth * 1.15;
        const ballRadius = clamp(game.width * 0.017, 6, 9);
        const autoTarget = game.vx > 0
          ? game.ballY + Math.sin(time / 450) * game.height * 0.025
          : game.height / 2;
        const autoStep = game.height * 0.44 * dt;
        game.autoY = clamp(game.autoY + clamp(autoTarget - game.autoY, -autoStep, autoStep), halfPaddle + 12, game.height - halfPaddle - 12);

        if (time >= game.serveAt) {
          game.ballX += game.vx * dt;
          game.ballY += game.vy * dt;
          if (game.ballY <= ballRadius + 12 || game.ballY >= game.height - ballRadius - 12) {
            game.ballY = clamp(game.ballY, ballRadius + 12, game.height - ballRadius - 12);
            game.vy *= -1;
          }
          const playerFace = paddleX + paddleWidth / 2;
          const autoFace = game.width - playerFace;
          if (game.vx < 0 && game.ballX - ballRadius <= playerFace && game.ballX > paddleX - paddleWidth
              && Math.abs(game.ballY - game.playerY) <= halfPaddle + ballRadius) {
            game.ballX = playerFace + ballRadius;
            game.vx = Math.min(Math.abs(game.vx) * 1.04, game.width * 1.05);
            game.vy = (game.ballY - game.playerY) / halfPaddle * game.height * 0.58;
            game.rally += 1;
            setRally(game.rally);
          } else if (game.vx > 0 && game.ballX + ballRadius >= autoFace && game.ballX < autoFace + paddleWidth
              && Math.abs(game.ballY - game.autoY) <= halfPaddle + ballRadius) {
            game.ballX = autoFace - ballRadius;
            game.vx = -Math.min(Math.abs(game.vx) * 1.035, game.width * 1.05);
            game.vy = (game.ballY - game.autoY) / halfPaddle * game.height * 0.49;
            game.rally += 1;
            setRally(game.rally);
          }
          if (game.ballX < -ballRadius || game.ballX > game.width + ballRadius) {
            if (game.ballX > game.width) game.playerScore += 1;
            else game.autoScore += 1;
            setScore({ player: game.playerScore, auto: game.autoScore });
            setRally(0);
            serve(game, game.ballX > game.width ? -1 : 1, 850);
          }
        }
        paint(ctx, game, reducedMotion);
      }
      frame = window.requestAnimationFrame(animate);
    };
    frame = window.requestAnimationFrame(animate);
    return () => { window.cancelAnimationFrame(frame); observer.disconnect(); visibilityObserver.disconnect(); };
  }, []);

  const movePaddle = (clientY: number) => {
    const bounds = canvasRef.current?.getBoundingClientRect();
    if (!bounds) return;
    const halfPaddle = gameRef.current.height * 0.11;
    gameRef.current.playerY = clamp(clientY - bounds.top, halfPaddle + 12, bounds.height - halfPaddle - 12);
  };

  return (
    <div className={styles.panel} aria-label="Playable Pongo table tennis demo">
      <div className={styles.header}>
        <div className={styles.heading}><span className={styles.liveDot} />PLAY THE RALLY</div>
        <div className={styles.scoreboard} aria-live="polite" aria-label={`You ${score.player}, opponent ${score.auto}`}>
          <span className={styles.youLabel}>YOU <strong>{score.player}</strong></span>
          <span className={styles.scoreDivider}>:</span>
          <span className={styles.autoLabel}><strong>{score.auto}</strong> AUTO</span>
        </div>
      </div>
      <canvas
        ref={canvasRef}
        className={styles.table}
        role="application"
        aria-label="Move your blue paddle with the pointer or arrow keys to return the ball. The orange opponent plays automatically."
        tabIndex={0}
        onPointerDown={(event) => {
          draggingRef.current = true;
          event.currentTarget.setPointerCapture(event.pointerId);
          movePaddle(event.clientY);
        }}
        onPointerMove={(event) => {
          if (draggingRef.current || event.pointerType === 'mouse') movePaddle(event.clientY);
        }}
        onPointerUp={() => { draggingRef.current = false; }}
        onPointerCancel={() => { draggingRef.current = false; }}
        onKeyDown={(event) => {
          if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
            event.preventDefault();
            movePaddle((canvasRef.current?.getBoundingClientRect().top ?? 0)
              + gameRef.current.playerY + (event.key === 'ArrowUp' ? -28 : 28));
          }
        }}
      />
      <div className={styles.footer}>
        <p>Move your blue paddle to return the ball.</p>
        <span>{rally ? `${rally} hit${rally === 1 ? '' : 's'}` : 'READY'}</span>
      </div>
    </div>
  );
}
