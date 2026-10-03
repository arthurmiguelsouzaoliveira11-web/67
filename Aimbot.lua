-- ============================================================
-- LUMINA STUDIO · Mobile UI em Lua (LÖVE 11.x)
-- Bolinha flutuante cinza → toca → abre painel com animação
-- ============================================================

local lg = love.graphics
local lm = love.math

-- ------------------------------------------------------------
-- CONSTANTES
-- ------------------------------------------------------------
local FAB_RADIUS      = 28          -- raio da bolinha flutuante
local FAB_MARGIN      = 22          -- margem da borda da tela
local PANEL_MAX_W     = 560         -- largura máxima do painel
local PANEL_RADIUS    = 24
local ANIM_SPEED      = 8           -- velocidade da animação

local COL = {
  bg1        = {0.04, 0.05, 0.08},
  bg2        = {0.07, 0.09, 0.16},
  glass      = {0.07, 0.09, 0.14, 0.94},
  border     = {1, 1, 1, 0.09},
  accent1    = {0.42, 0.49, 1.0},
  accent2    = {0.72, 0.42, 1.0},
  text       = {0.93, 0.95, 0.98},
  textDim    = {0.61, 0.65, 0.75},
  textMuted  = {0.42, 0.46, 0.57},
  fabTop     = {0.62, 0.65, 0.75},
  fabMid     = {0.42, 0.46, 0.57},
  fabBot     = {0.28, 0.31, 0.40},
  fabShadow  = {0, 0, 0, 0.55},
}

-- ------------------------------------------------------------
-- FONTES
-- ------------------------------------------------------------
local F = {}

local function newFont(size)
  local ok, font = pcall(lg.newFont, size)
  if ok and font then return font end
  return lg.newFont(size)
end

local function loadFonts()
  F.title    = newFont(20)
  F.subtitle = newFont(11)
  F.body     = newFont(15)
  F.small    = newFont(12)
  F.tiny     = newFont(10)
  F.big      = newFont(26)
end

-- ------------------------------------------------------------
-- ESTADO GLOBAL
-- ------------------------------------------------------------
local slidersConfig = {
  { id="saturation",  label="Saturação",  min=0,   max=200, step=1,    default=100, unit="%" },
  { id="brightness",  label="Brilho",     min=0,   max=200, step=1,    default=100, unit="%" },
  { id="contrast",    label="Contraste",  min=0,   max=200, step=1,    default=100, unit="%" },
  { id="blur",        label="Desfoque",   min=0,   max=15,  step=0.1,  default=0,   unit="px"},
  { id="exposure",    label="Exposição",  min=0.2, max=2.5, step=0.01, default=1,   unit="x" },
  { id="light",       label="Luz",        min=0,   max=2,   step=0.01, default=1,   unit="x" },
  { id="temperature", label="Temperatura",min=-100,max=100, step=1,    default=0,   unit=""  },
  { id="shadows",     label="Sombras",    min=0,   max=100, step=1,    default=0,   unit="%" },
  { id="highlights",  label="Realces",    min=0,   max=100, step=1,    default=0,   unit="%" },
  { id="opacity",     label="Opacidade",  min=0,   max=100, step=1,    default=100, unit="%" },
  { id="sharpness",   label="Nitidez",    min=0,   max=100, step=1,    default=0,   unit="%" },
}

local current = {}
local defaults = {}
for _, s in ipairs(slidersConfig) do
  current[s.id] = s.default
  defaults[s.id] = s.default
end

-- Estações
local seasons = {
  { id="outono",    nome="Outono",    img="assets/outono.jpg"    },
  { id="inverno",   nome="Inverno",   img="assets/inverno.jpg"   },
  { id="primavera", nome="Primavera", img="assets/primavera.jpg" },
  { id="verao",     nome="Verão",     img="assets/verao.jpg"     },
}
local selectedSeason = 1

-- Presets
local presets = {
  { nome="Outono Cinematográfico", season=1, fx={ saturation=115, brightness=95,  contrast=118, blur=0.3, exposure=0.95, light=1.05, temperature=35,  shadows=15, highlights=5,  opacity=100, sharpness=20 } },
  { nome="Inverno Gelado",         season=2, fx={ saturation=85,  brightness=105, contrast=110, blur=0.5, exposure=1.05, light=0.95, temperature=-55, shadows=25, highlights=10, opacity=100, sharpness=15 } },
  { nome="Primavera Vibrante",     season=3, fx={ saturation=145, brightness=110, contrast=105, blur=0,   exposure=1.1,  light=1.15, temperature=15,  shadows=5,  highlights=15, opacity=100, sharpness=35 } },
  { nome="Verão Dourado",          season=4, fx={ saturation=135, brightness=108, contrast=112, blur=0,   exposure=1.15, light=1.25, temperature=45,  shadows=10, highlights=20, opacity=100, sharpness=25 } },
}

-- Toast
local toast = { msg="", icon="*", timer=0, alpha=0 }

-- Estado do painel
local panel = {
  open = false,
  anim = 0,       -- 0 = fechado, 1 = aberto
  target = 0,
}

-- Toque/clique
local touches = {}          -- toques ativos
local taps = {}             -- toques "novos" neste frame
local presses = {}          -- toques que acabaram neste frame

-- Imagens
local images = {}
local shader

-- ------------------------------------------------------------
-- IMAGENS (fallback colorido se arquivo não existir)
-- ------------------------------------------------------------
local function makeFallback(w, h, baseColor)
  local canvas = lg.newCanvas(w, h)
  lg.setCanvas(canvas)
  lg.clear(baseColor[1]*0.5, baseColor[2]*0.5, baseColor[3]*0.5, 1)
  for i = 0, 30 do
    local t = i / 30
    lg.setColor(
      baseColor[1]*(1-t*0.6),
      baseColor[2]*(1-t*0.6),
      baseColor[3]*(1-t*0.6),
      1
    )
    lg.rectangle("fill", 0, h*t, w, h/30 + 1)
  end
  lg.setCanvas()
  lg.setColor(1, 1, 1, 1)
  return canvas
end

local function loadImage(path, w, h, baseColor)
  local ok, img = pcall(lg.newImage, path)
  if ok and img then return img end
  return makeFallback(w, h, baseColor)
end

-- Cores de fallback por estação
local fallbackColors = {
  {0.85, 0.50, 0.20},  -- outono
  {0.60, 0.75, 0.95},  -- inverno
  {0.95, 0.65, 0.80},  -- primavera
  {1.00, 0.85, 0.40},  -- verão
}

-- ------------------------------------------------------------
-- SHADER (aplica filtros em tempo real)
-- ------------------------------------------------------------
local SHADER_SRC = [[
extern vec2 texSize;
extern float saturation;
extern float brightness;
extern float contrast;
extern float exposure;
extern float temperature;
extern float shadows;
extern float highlights;
extern float sharpness;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  vec3 col = c.rgb;

  col *= exposure * brightness;
  col = (col - 0.5) * contrast + 0.5;

  float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = mix(vec3(lum), col, saturation);

  col.r += temperature * 0.15;
  col.b -= temperature * 0.15;

  float shadowMask = 1.0 - smoothstep(0.0, 0.5, lum);
  col += shadows * shadowMask * 0.3;

  float highMask = smoothstep(0.5, 1.0, lum);
  col += highlights * highMask * 0.3;

  if (sharpness > 0.0) {
    vec2 px = vec2(1.0/texSize.x, 1.0/texSize.y);
    vec3 b = (Texel(tex, tc + vec2(-px.x, 0)).rgb +
              Texel(tex, tc + vec2( px.x, 0)).rgb +
              Texel(tex, tc + vec2(0, -px.y)).rgb +
              Texel(tex, tc + vec2(0,  px.y)).rgb) * 0.25;
    col = col + (col - b) * sharpness;
  }

  col = clamp(col, 0.0, 1.0);
  return vec4(col, c.a) * color;
}
]]

-- ------------------------------------------------------------
-- UTILITÁRIOS
-- ------------------------------------------------------------
local function showToast(msg, icon)
  toast.msg = msg
  toast.icon = icon or "✓"
  toast.timer = 2.0
  toast.alpha = 1
end

local function pointInRect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

local function pointInCircle(px, py, cx, cy, r)
  local dx, dy = px - cx, py - cy
  return dx*dx + dy*dy <= r*r
end

local function lerp(a, b, t) return a + (b - a) * t end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function applyPreset(p)
  if p.season then selectedSeason = p.season end
  for k, v in pairs(p.fx) do
    if current[k] ~= nil then current[k] = v end
  end
end

local function resetDefaults()
  for k, v in pairs(defaults) do current[k] = v end
end

-- ------------------------------------------------------------
-- LAYOUT (recalculado no resize)
-- ------------------------------------------------------------
local layout = {
  sw = 720, sh = 1280,
  fabX = 0, fabY = 0,
  panelX = 0, panelY = 0, panelW = 0, panelH = 0,
  -- áreas internas
  previewY = 0, previewH = 0,
  seasonsY = 0,
  slidersY = 0,
  presetsY = 0,
  actionsY = 0,
  -- scroll
  scrollY = 0,
  contentH = 0,
}

local function computeLayout()
  local sw, sh = lg.getDimensions()
  layout.sw, layout.sh = sw, sh

  -- FAB
  layout.fabX = sw - FAB_RADIUS - FAB_MARGIN
  layout.fabY = sh - FAB_RADIUS - FAB_MARGIN

  -- Painel
  local pw = math.min(sw, PANEL_MAX_W)
  local ph = math.floor(sh * 0.92)
  layout.panelW = pw
  layout.panelH = ph
  layout.panelX = (sw - pw) / 2
  layout.panelY = sh - ph  -- começa na parte de baixo

  -- Conteúdo interno
  local padX = 20
  local contentX = layout.panelX + padX
  local contentW = pw - padX * 2
  local y = layout.panelY + 92   -- abaixo do header do painel

  -- Preview
  layout.previewY = y
  layout.previewH = math.floor(contentW * 0.62)
  y = y + layout.previewH + 24

  -- Estações
  layout.seasonsY = y
  y = y + 130   -- título + cards

  -- Sliders (grid 2 colunas, 6 linhas)
  layout.slidersY = y
  y = y + 30 + math.ceil(#slidersConfig / 2) * 62

  -- Presets
  layout.presetsY = y
  y = y + 30 + math.ceil(#presets / 2) * 54

  -- Ações
  layout.actionsY = y
  y = y + 60

  layout.contentH = y - (layout.panelY + 92)
end

-- ------------------------------------------------------------
-- LOVE.LOAD
-- ------------------------------------------------------------
function love.load()
  lg.setDefaultFilter("linear", "linear")
  loadFonts()

  -- Carrega imagens
  for i, s in ipairs(seasons) do
    images[i] = loadImage(s.img, 900, 560, fallbackColors[i])
  end

  -- Shader
  local ok, s = pcall(lg.newShader, SHADER_SRC)
  if ok then shader = s end

  computeLayout()
  showToast("Lumina Studio pronto", "✓")
end

-- ------------------------------------------------------------
-- LOVE.RESIZE
-- ------------------------------------------------------------
function love.resize(w, h)
  computeLayout()
end

-- ------------------------------------------------------------
-- INPUT (mobile + mouse)
-- ------------------------------------------------------------
local function handlePress(x, y)
  -- Se o painel está aberto, trata cliques internos
  if panel.open then
    -- Botão fechar
    local closeSize = 38
    local closeX = layout.panelX + layout.panelW - closeSize - 16
    local closeY = layout.panelY + 18
    if pointInRect(x, y, closeX, closeY, closeSize, closeSize) then
      panel.target = 0
      return
    end

    -- Estações
    local cardW = (layout.panelW - 40 - 3*10) / 4
    local cardH = cardW
    local seasonsStartX = layout.panelX + 20
    local seasonsCardsY = layout.seasonsY + 34
    for i = 1, #seasons do
      local cx = seasonsStartX + (i-1) * (cardW + 10)
      if pointInRect(x, y, cx, seasonsCardsY - layout.scrollY, cardW, cardH + 30) then
        selectedSeason = i
        showToast("Estação: " .. seasons[i].nome, "✓")
        return
      end
    end

    -- Presets
    local pGap = 10
    local pW = (layout.panelW - 40 - pGap) / 2
    local pH = 44
    local pStartX = layout.panelX + 20
    local pStartY = layout.presetsY + 34 - layout.scrollY
    for i = 1, #presets do
      local col = (i-1) % 2
      local row = math.floor((i-1) / 2)
      local px = pStartX + col * (pW + pGap)
      local py = pStartY + row * (pH + 8)
      if pointInRect(x, y, px, py, pW, pH) then
        applyPreset(presets[i])
        showToast("Preset: " .. presets[i].nome, "✓")
        return
      end
    end

    -- Botões de ação
    local btnW = (layout.panelW - 40 - 10) / 2
    local btnH = 46
    local btnY = layout.actionsY - layout.scrollY
    local btnX1 = layout.panelX + 20
    local btnX2 = btnX1 + btnW + 10
    if pointInRect(x, y, btnX1, btnY, btnW, btnH) then
      resetDefaults()
      showToast("Padrões restaurados", "↺")
      return
    end
    if pointInRect(x, y, btnX2, btnY, btnW, btnH) then
      showToast("Efeitos aplicados", "✓")
      return
    end

    -- Sliders (arraste)
    local slidersStartX = layout.panelX + 20
    local slidersStartY = layout.slidersY + 34 - layout.scrollY
    local colW = (layout.panelW - 40 - 16) / 2
    local rowH = 62
    for i, s in ipairs(slidersConfig) do
      local col = (i-1) % 2
      local row = math.floor((i-1) / 2)
      local sx = slidersStartX + col * (colW + 16)
      local sy = slidersStartY + row * rowH
      if pointInRect(x, y, sx, sy + 22, colW, 20) then
        local t = clamp((x - sx) / colW, 0, 1)
        local raw = s.min + (s.max - s.min) * t
        raw = math.floor(raw / s.step + 0.5) * s.step
        current[s.id] = raw
        -- guarda qual slider está sendo arrastado
        layout.activeSlider = { id = s.id, x = sx, w = colW, y0 = sy + 22, h = 20 }
        return
      end
    end

    return
  end

  -- Painel fechado: só FAB
  if pointInCircle(x, y, layout.fabX, layout.fabY, FAB_RADIUS + 4) then
    panel.target = 1
    showToast("Abrindo editor...", "✦")
  end
end

local function handleMove(x, y)
  -- Arraste de slider
  if panel.open and layout.activeSlider then
    local s
    for _, cfg in ipairs(slidersConfig) do
      if cfg.id == layout.activeSlider.id then s = cfg break end
    end
    if s then
      local t = clamp((x - layout.activeSlider.x) / layout.activeSlider.w, 0, 1)
      local raw = s.min + (s.max - s.min) * t
      raw = math.floor(raw / s.step + 0.5) * s.step
      current[s.id] = raw
    end
  end
end

local function handleRelease()
  layout.activeSlider = nil
end

function love.mousepressed(x, y, button)
  if button == 1 then handlePress(x, y) end
end

function love.mousemoved(x, y)
  handleMove(x, y)
end

function love.mousereleased()
  handleRelease()
end

-- Touch (mobile)
function love.touchpressed(id, x, y)
  handlePress(x, y)
end

function love.touchmoved(id, x, y)
  handleMove(x, y)
end

function love.touchreleased(id)
  handleRelease()
end

function love.keypressed(key)
  if key == "escape" then
    if panel.open then
      panel.target = 0
    else
      love.event.quit()
    end
  end
end

-- ------------------------------------------------------------
-- UPDATE
-- ------------------------------------------------------------
function love.update(dt)
  -- Animação do painel
  local speed = ANIM_SPEED * dt
  local diff = panel.target - panel.anim
  if math.abs(diff) < 0.001 then
    panel.anim = panel.target
  else
    panel.anim = panel.anim + diff * math.min(1, speed)
  end
  panel.open = panel.anim > 0.01

  -- Toast
  if toast.timer > 0 then
    toast.timer = toast.timer - dt
    toast.alpha = math.min(1, toast.alpha + dt * 5)
  else
    toast.alpha = math.max(0, toast.alpha - dt * 3)
  end

  -- Scroll do painel (mouse wheel para desktop)
  if panel.open then
    -- limita scroll
    local maxScroll = math.max(0, layout.contentH - (layout.panelH - 92))
    layout.scrollY = clamp(layout.scrollY, 0, maxScroll)
  end
end

-- ------------------------------------------------------------
-- SCROLL
-- ------------------------------------------------------------
function love.wheelmoved(x, y)
  if panel.open then
    layout.scrollY = layout.scrollY - y * 40
  end
end

-- ------------------------------------------------------------
-- DRAW
-- ------------------------------------------------------------
function love.draw()
  local sw, sh = lg.getDimensions()

  -- Fundo
  drawBackground(sw, sh)

  -- Painel (se anim > 0)
  if panel.anim > 0.01 then
    drawPanel()
  end

  -- FAB (some quando painel está aberto)
  local fabAlpha = 1 - panel.anim
  if fabAlpha > 0.01 then
    drawFab(fabAlpha)
  end

  -- Toast
  drawToast(sw, sh)
end

-- ------------------------------------------------------------
-- FUNDO
-- ------------------------------------------------------------
function drawBackground(w, h)
  for y = 0, h, 4 do
    local t = y / h
    lg.setColor(
      COL.bg1[1] + (COL.bg2[1]-COL.bg1[1])*t,
      COL.bg1[2] + (COL.bg2[2]-COL.bg1[2])*t,
      COL.bg1[3] + (COL.bg2[3]-COL.bg1[3])*t,
      1
    )
    lg.rectangle("fill", 0, y, w, 4)
  end
  lg.setColor(COL.accent1[1], COL.accent1[2], COL.accent1[3], 0.08)
  lg.circle("fill", w*0.15, h*0.2, math.min(w, h)*0.5)
  lg.setColor(COL.accent2[1], COL.accent2[2], COL.accent2[3], 0.07)
  lg.circle("fill", w*0.85, h*0.85, math.min(w, h)*0.45)
  lg.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------
-- BOLINHA FLUTUANTE (FAB)
-- ------------------------------------------------------------
function drawFab(alpha)
  local cx, cy = layout.fabX, layout.fabY
  local r = FAB_RADIUS

  -- Pulso de fundo
  local t = love.timer.getTime()
  local pulse = 1 + 0.5 * (0.5 + 0.5 * math.sin(t * 2.5))
  lg.setColor(COL.fabMid[1], COL.fabMid[2], COL.fabMid[3], alpha * 0.25)
  lg.circle("fill", cx, cy, r * pulse)

  -- Sombra
  lg.setColor(0, 0, 0, alpha * 0.55)
  lg.circle("fill", cx, cy + 4, r)

  -- Gradiente radial (aproximado com círculos concêntricos)
  local steps = 12
  for i = steps, 1, -1 do
    local t2 = (i - 1) / steps
    local rr = r * (0.15 + 0.85 * t2)
    local mix = 1 - t2
    -- interpola entre fabTop e fabBot
    local cr = lerp(COL.fabBot[1], COL.fabTop[1], mix)
    local cg = lerp(COL.fabBot[2], COL.fabTop[2], mix)
    local cb = lerp(COL.fabBot[3], COL.fabTop[3], mix)
    lg.setColor(cr, cg, cb, alpha)
    lg.circle("fill", cx, cy, rr)
  end

  -- Borda sutil
  lg.setColor(1, 1, 1, alpha * 0.12)
  lg.setLineWidth(1)
  lg.circle("line", cx, cy, r)

  -- Brilho superior
  lg.setColor(1, 1, 1, alpha * 0.35)
  lg.circle("fill", cx - r*0.3, cy - r*0.35, r*0.22)

  lg.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------
-- PAINEL
-- ------------------------------------------------------------
function drawPanel()
  local a = panel.anim
  local px, py, pw, ph = layout.panelX, layout.panelY, layout.panelW, layout.panelH

  -- Offset de animação (slide de baixo para cima)
  local slide = (1 - a) * ph
  py = py + slide

  -- Backdrop
  lg.setColor(0, 0, 0, 0.65 * a)
  lg.rectangle("fill", 0, 0, layout.sw, layout.sh)

  -- Sombra do painel
  lg.setColor(0, 0, 0, 0.6 * a)
  lg.rectangle("fill", px + 3, py + 8, pw, ph, PANEL_RADIUS, PANEL_RADIUS)

  -- Corpo do painel (glass)
  lg.setColor(COL.glass[1], COL.glass[2], COL.glass[3], a)
  lg.rectangle("fill", px, py, pw, ph, PANEL_RADIUS, PANEL_RADIUS)

  -- Borda
  lg.setColor(COL.border)
  lg.setLineWidth(1)
  lg.rectangle("line", px, py, pw, ph, PANEL_RADIUS, PANEL_RADIUS)

  -- Grabber
  lg.setColor(1, 1, 1, 0.18 * a)
  lg.rectangle("fill", px + pw/2 - 22, py + 10, 44, 5, 3, 3)

  -- Header do painel
  drawPanelHeader(px, py, pw, a)

  -- Área de conteúdo com clip
  local contentX = px + 20
  local contentY = py + 92
  local contentW = pw - 40
  local contentH = ph - 92

  -- Clip do conteúdo para scroll
  lg.setScissor(contentX - 20, contentY, contentW + 40, contentH)

  local sy = contentY - layout.scrollY

  -- Preview
  drawPreview(contentX, sy + (layout.previewY - (layout.panelY + 92)), contentW, layout.previewH)

  -- Estações
  drawSeasons(contentX, sy + (layout.seasonsY - (layout.panelY + 92)), contentW)

  -- Sliders
  drawSliders(contentX, sy + (layout.slidersY - (layout.panelY + 92)), contentW)

  -- Presets
  drawPresets(contentX, sy + (layout.presetsY - (layout.panelY + 92)), contentW)

  -- Ações
  drawActions(contentX, sy + (layout.actionsY - (layout.panelY + 92)), contentW)

  lg.setScissor()

  lg.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------
-- HEADER DO PAINEL
-- ------------------------------------------------------------
function drawPanelHeader(px, py, pw, a)
  -- Ícone
  local iconX = px + 20
  local iconY = py + 26
  local iconSize = 42
  lg.setColor(COL.accent1[1], COL.accent1[2], COL.accent1[3], a)
  lg.rectangle("fill", iconX, iconY, iconSize, iconSize, 12, 12)
  lg.setColor(1, 1, 1, a)
  lg.setFont(F.title)
  lg.printf("✦", iconX, iconY + 8, iconSize, "center")

  -- Título
  lg.setColor(COL.text[1], COL.text[2], COL.text[3], a)
  lg.setFont(F.title)
  lg.print("Lumina Studio", iconX + iconSize + 12, iconY + 3)
  lg.setColor(COL.textMuted[1], COL.textMuted[2], COL.textMuted[3], a)
  lg.setFont(F.tiny)
  lg.print("EDITOR VISUAL", iconX + iconSize + 12, iconY + 28)

  -- Botão fechar
  local closeSize = 38
  local closeX = px + pw - closeSize - 16
  local closeY = py + 26
  lg.setColor(1, 1, 1, 0.06 * a)
  lg.circle("fill", closeX + closeSize/2, closeY + closeSize/2, closeSize/2)
  lg.setColor(1, 1, 1, 0.10 * a)
  lg.setLineWidth(1)
  lg.circle("line", closeX + closeSize/2, closeY + closeSize/2, closeSize/2)
  lg.setColor(COL.text[1], COL.text[2], COL.text[3], a)
  lg.setFont(F.body)
  lg.printf("✕", closeX, closeY + 8, closeSize, "center")

  -- Linha divisória
  lg.setColor(1, 1, 1, 0.06 * a)
  lg.rectangle("fill", px + 16, py + 82, pw - 32, 1)
end

-- ------------------------------------------------------------
-- PREVIEW
-- ------------------------------------------------------------
function drawPreview(x, y, w, h)
  -- Container
  lg.setColor(0.05, 0.06, 0.10, 1)
  lg.rectangle("fill", x, y, w, h, 18, 18)
  lg.setColor(1, 1, 1, 0.05)
  lg.setLineWidth(1)
  lg.rectangle("line", x, y, w, h, 18, 18)

  local img = images[selectedSeason]
  if not img then return end

  local iw, ih = img:getDimensions()
  local pad = 8
  local cw, ch = w - pad*2, h - pad*2
  local scale = math.max(cw / iw, ch / ih)
  local dw, dh = iw * scale, ih * scale
  local dx = x + pad + (cw - dw)/2
  local dy = y + pad + (ch - dh)/2

  if shader then
    shader:send("texSize", {iw, ih})
    shader:send("saturation", current.saturation / 100)
    shader:send("brightness", current.brightness / 100)
    shader:send("contrast",   current.contrast   / 100)
    shader:send("exposure",   current.exposure * current.light)
    shader:send("temperature", current.temperature / 100)
    shader:send("shadows",    current.shadows / 100)
    shader:send("highlights", current.highlights / 100)
    shader:send("sharpness",  current.sharpness / 100)
    lg.setShader(shader)
  end

  lg.setColor(1, 1, 1, current.opacity / 100)
  lg.draw(img, dx, dy, 0, scale, scale)

  lg.setShader()
  lg.setColor(1, 1, 1, 1)

  -- Badge
  local bx, by = x + 14, y + 14
  lg.setColor(0, 0, 0, 0.6)
  lg.rectangle("fill", bx, by, 150, 26, 13, 13)
  lg.setColor(1, 1, 1, 0.12)
  lg.setLineWidth(1)
  lg.rectangle("line", bx, by, 150, 26, 13, 13)

  local pulse = 0.6 + 0.4 * math.abs(math.sin(love.timer.getTime() * 2))
  lg.setColor(0.3, 0.87, 0.5, pulse)
  lg.circle("fill", bx + 14, by + 13, 4)
  lg.set
