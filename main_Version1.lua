-- Tiny Hollow Knight–style demo for LÖVE (Love2D)
-- Save this as main.lua inside a folder and run with `love <folder>`.

local lg = love.graphics
local lk = love.keyboard
local audio = love.audio

local W, H = 960, 600
love.window.setMode(W, H, {resizable=false, vsync=true})
love.window.setTitle("Hollow Knight - Tiny Demo (Love2D)")

-- State
local started = false

-- Utilities
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function rectsOverlap(a, b)
    return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

-- Level (simple platforms)
local platforms = {
    {x=0,   y=540, w=960, h=60}, -- ground
    {x=140, y=420, w=220, h=20},
    {x=420, y=360, w=220, h=20},
    {x=740, y=300, w=160, h=20},
    {x=560, y=480, w=120, h=20},
    {x=20,  y=300, w=100, h=20},
}

local goal = {x=880, y=240, w=40, h=40, reached=false}

-- Player
local player = {
    x=60, y=460, w=28, h=36,
    vx=0, vy=0,
    dir=1, onGround=false,
    jumps=0, maxJumps=1,
    canDash=true, dashTimer=0, dashCooldown=0,
    attackTimer=0,
    health=5, maxHealth=5,
    geo=0,
    respawn={x=60, y=460}
}

local GRAVITY = 1400
local MOVE_ACCEL = 2200
local MAX_RUN = 260
local FRICTION = 0.85
local JUMP_V = -520
local DASH_SPEED = 680
local DASH_TIME = 0.12
local DASH_COOLDOWN = 0.8
local ATTACK_TIME = 0.18

-- Enemy
local function makeEnemy(x,y)
    return {
        x=x, y=y, w=32, h=32,
        vx=60, leftBound=x-120, rightBound=x+120,
        health=3, alive=true, hurtTimer=0
    }
end
local enemy = makeEnemy(520, 320)

-- FPS tracking
local fps = 0
local fpsAccum = 0
local fpsCount = 0

-- Simple beep generator (sine wave) -> returns a Source that can be played
local function makeBeep(freq, duration, volume)
    volume = volume or 0.1
    local sr = 44100
    local len = math.floor(duration * sr)
    local sd = love.sound.newSoundData(len, sr, 16, 1)
    for i = 0, len-1 do
        local t = i / sr
        local sample = math.sin(2 * math.pi * freq * t) * volume
        sd:setSample(i, sample)
    end
    return audio.newSource(sd, "static")
end

local beeps = {
    jump = makeBeep(520, 0.04, 0.08),
    dash = makeBeep(840, 0.04, 0.09),
    attack = makeBeep(660, 0.03, 0.1),
    hit = makeBeep(440, 0.04, 0.1),
    die = makeBeep(220, 0.18, 0.12),
    hurt = makeBeep(160, 0.08, 0.12),
    goal = makeBeep(980, 0.18, 0.12),
}

local function playBeep(name)
    local s = beeps[name]
    if s then
        -- stop and replay to allow quick successive plays
        if s:isPlaying() then s:stop() end
        s:play()
    end
end

-- Reset player
local function resetPlayer()
    player.x = player.respawn.x
    player.y = player.respawn.y
    player.vx = 0
    player.vy = 0
    player.health = player.maxHealth
    player.dashTimer = 0
    player.canDash = true
    player.attackTimer = 0
end

-- Input state helpers
local input = {}
local function isDown(k)
    return lk.isDown(k) or false
end

-- Love callbacks
function love.keypressed(key)
    if key == "return" and not started then
        started = true
    end

    if not started then return end

    if key == "z" or key == "space" then
        -- Jump
        if player.onGround or player.jumps < player.maxJumps then
            player.vy = JUMP_V
            player.jumps = player.jumps + 1
            player.onGround = false
            playBeep("jump")
        end
    elseif key == "x" or key == "k" then
        -- Attack
        if player.attackTimer <= 0 then
            player.attackTimer = ATTACK_TIME
            playBeep("attack")
        end
    elseif key == "c" then
        -- Dash
        if player.canDash and player.dashTimer <= 0 and player.dashCooldown <= 0 then
            player.dashTimer = DASH_TIME
            player.canDash = false
            player.dashCooldown = DASH_COOLDOWN
            player.vx = player.dir * DASH_SPEED
            player.vy = 0
            playBeep("dash")
        end
    elseif key == "r" then
        resetPlayer()
        goal.reached = false
        if not enemy.alive then enemy = makeEnemy(520, 320) end
    end
end

function love.update(dt)
    if not started then return end
    -- clamp dt to avoid large steps
    dt = math.min(dt, 0.032)

    -- Movement input
    local move = 0
    if isDown("left") or isDown("a") then move = move - 1 end
    if isDown("right") or isDown("d") then move = move + 1 end

    if math.abs(move) > 0 then
        player.vx = player.vx + move * MOVE_ACCEL * dt
        player.dir = move > 0 and 1 or -1
    else
        player.vx = player.vx * (FRICTION ^ (dt * 60))
    end
    player.vx = clamp(player.vx, -MAX_RUN, MAX_RUN)

    -- Dash timers
    if player.dashTimer > 0 then
        player.dashTimer = player.dashTimer - dt
        player.vx = player.vx * 0.99
    else
        if player.dashCooldown > 0 then
            player.dashCooldown = player.dashCooldown - dt
        else
            player.canDash = true
        end
    end

    -- Attack timer decrement
    if player.attackTimer > 0 then
        player.attackTimer = math.max(0, player.attackTimer - dt)
    end

    -- Gravity & integration
    if player.dashTimer <= 0 then
        player.vy = player.vy + GRAVITY * dt
    end
    player.x = player.x + player.vx * dt
    player.y = player.y + player.vy * dt

    -- Simple collisions with platforms (AABB)
    player.onGround = false
    for _, p in ipairs(platforms) do
        if player.x < p.x + p.w and player.x + player.w > p.x and player.y < p.y + p.h and player.y + player.h > p.y then
            -- compute penetration on both axes
            local px = (player.x + player.w/2) - (p.x + p.w/2)
            local py = (player.y + player.h/2) - (p.y + p.h/2)
            local overlapX = (player.w + p.w)/2 - math.abs(px)
            local overlapY = (player.h + p.h)/2 - math.abs(py)
            if overlapX < overlapY then
                -- resolve X
                if px > 0 then player.x = player.x + overlapX else player.x = player.x - overlapX end
                player.vx = 0
            else
                -- resolve Y
                if py > 0 then
                    player.y = player.y + overlapY
                    player.vy = 0
                else
                    player.y = player.y - overlapY
                    player.vy = 0
                    player.onGround = true
                    player.jumps = 0
                end
            end
        end
    end

    -- Attack hitbox
    local attackHit = {
        x = (player.dir > 0) and (player.x + player.w) or (player.x - 32),
        y = player.y + 6,
        w = 32,
        h = player.h - 12,
        active = player.attackTimer > 0
    }

    -- Enemy AI
    if enemy.alive then
        if enemy.hurtTimer <= 0 then
            enemy.x = enemy.x + enemy.vx * dt
            if enemy.x < enemy.leftBound then enemy.x = enemy.leftBound; enemy.vx = math.abs(enemy.vx) end
            if enemy.x > enemy.rightBound then enemy.x = enemy.rightBound; enemy.vx = -math.abs(enemy.vx) end
        else
            enemy.hurtTimer = enemy.hurtTimer - dt
        end
    end

    -- Attack enemy
    if attackHit.active and enemy.alive and rectsOverlap(attackHit, enemy) then
        enemy.health = enemy.health - 1
        enemy.hurtTimer = 0.25
        enemy.vx = -enemy.vx
        player.geo = player.geo + 5
        playBeep("hit")
        player.attackTimer = 0
        if enemy.health <= 0 then
            enemy.alive = false
            playBeep("die")
            player.geo = player.geo + 15
        end
    end

    -- Enemy hurts player on contact
    if enemy.alive and rectsOverlap(player, enemy) and enemy.hurtTimer <= 0 then
        player.health = player.health - 1
        player.vx = (player.x < enemy.x) and -220 or 220
        player.vy = -180
        enemy.hurtTimer = 0.2
        playBeep("hurt")
        if player.health <= 0 then
            player.health = 0
            player.geo = math.max(0, math.floor(player.geo * 0.5))
            -- temporary hide then respawn
            player.x = -10000; player.y = -10000
            -- schedule respawn
            love.timer.sleep(0) -- ensure responsiveness; actual delay below
            -- use a timer via coroutine-like simple approach: set a respawn tick
            player._respawn_timer = 0.6
        end
    end

    -- handle player._respawn_timer if present
    if player._respawn_timer then
        player._respawn_timer = player._respawn_timer - dt
        if player._respawn_timer <= 0 then
            player._respawn_timer = nil
            resetPlayer()
        end
    end

    -- Goal check
    if not goal.reached and (player.x + player.w > goal.x) and (player.y + player.h > goal.y) then
        goal.reached = true
        playBeep("goal")
    end

    -- Fall out of world => respawn
    if player.y > H + 200 then
        player.geo = math.max(0, math.floor(player.geo * 0.5))
        resetPlayer()
    end

    -- FPS tracking
    fpsCount = fpsCount + 1
    fpsAccum = fpsAccum + dt
    if fpsAccum >= 1 then
        fps = fpsCount
        fpsCount = 0
        fpsAccum = fpsAccum - 1
    end

    if math.abs(player.vx) < 0.01 then player.vx = 0 end
end

function love.draw()
    -- background
    lg.clear(0.044, 0.086, 0.125) -- dark bluish

    -- subtle gradient (approx)
    local g = lg.newCanvas(W, H)
    lg.setCanvas(g)
    lg.clear()
    local grad = {0.07,0.125,0.16, 0.03,0.06,0.09}
    -- approximate by a rectangle overlay
    lg.setColor(0.07, 0.125, 0.16)
    lg.rectangle("fill", 0, 0, W, H)
    lg.setColor(0.03, 0.06, 0.09, 0.5)
    lg.rectangle("fill", 0, 0, W, H)
    lg.setCanvas()
    lg.setColor(1,1,1,0.06)
    lg.draw(g, 0, 0)
    lg.setColor(1,1,1,1)

    -- platforms
    for i,p in ipairs(platforms) do
        if i == 1 then
            lg.setColor(0.03, 0.086, 0.098)
        else
            lg.setColor(0.027, 0.102, 0.141)
        end
        lg.rectangle("fill", p.x, p.y, p.w, p.h)
        lg.setColor(0.07, 0.2, 0.243)
        lg.rectangle("fill", p.x, p.y, p.w, 4)
    end

    -- goal
    if goal.reached then lg.setColor(0.62, 0.82, 0.7) else lg.setColor(0.97, 0.82, 0.54) end
    lg.rectangle("fill", goal.x, goal.y, goal.w, goal.h)
    lg.setColor(0.23, 0.18, 0.125)
    lg.rectangle("line", goal.x, goal.y, goal.w, goal.h)
    lg.setColor(0.11, 0.17, 0.21)
    lg.rectangle("fill", goal.x+6, goal.y+6, goal.w-12, goal.h-12)

    -- enemy
    if enemy.alive then
        if enemy.hurtTimer > 0 then lg.setColor(1, 0.6, 0.6) else lg.setColor(0.42, 0.56, 0.63) end
        lg.rectangle("fill", enemy.x, enemy.y, enemy.w, enemy.h)
        lg.setColor(0.07,0.07,0.07)
        lg.rectangle("fill", enemy.x + (enemy.w/2 - 6), enemy.y + 6, 4, 4)
        lg.rectangle("fill", enemy.x + (enemy.w/2 + 4), enemy.y + 6, 4, 4)
    else
        lg.setColor(0.23,0.23,0.23)
        lg.rectangle("fill", enemy.x + 6, enemy.y + enemy.h/2, 20, 4)
    end

    -- player
    lg.push()
    lg.translate(player.x, player.y)
    -- shadow
    lg.setColor(0,0,0,0.25)
    lg.rectangle("fill", 6, player.h-4, player.w-4, 4)
    -- body
    lg.setColor(0.91,0.93,0.96)
    lg.rectangle("fill", 0, 0, player.w, player.h)
    -- cloak
    lg.setColor(0.043, 0.137, 0.188)
    lg.polygon("fill", player.w/2, 4, player.w+8, player.h/2, player.w/2, player.h-6)
    -- mask / eyes
    lg.setColor(0.043,0.07,0.12)
    lg.rectangle("fill", 6, 8, player.w-12, 8)
    lg.setColor(1,1,1)
    lg.rectangle("fill", player.w/2 - 6, 10, 4, 4)
    lg.rectangle("fill", player.w/2 + 4, 10, 4, 4)
    lg.pop()

    -- attack hitbox visual
    if player.attackTimer > 0 then
        lg.setColor(1, 0.9, 0.7, 0.55)
        local ax = (player.dir > 0) and (player.x + player.w) or (player.x - 32)
        lg.rectangle("fill", ax, player.y + 6, 32, player.h - 12)
    end

    -- HUD
    lg.setColor(1,1,1)
    lg.setFont(lg.newFont(16))
    local hearts = string.rep("❤", player.health) .. string.rep("♡", player.maxHealth - player.health)
    lg.print("Health: " .. hearts, 18, 18)
    lg.print("Geo: " .. tostring(player.geo), 18, 42)
    lg.print("Dash: " .. (player.canDash and "Ready" or string.format("%.1fs", math.max(0, player.dashCooldown))), 18, 66)
    lg.print("FPS: " .. tostring(fps), W - 110, 18)

    -- start overlay
    if not started then
        lg.setColor(0,0,0,0.75)
        lg.rectangle("fill", W/2 - 260, H/2 - 100, 520, 200)
        lg.setColor(1,1,1)
        lg.setFont(lg.newFont(20))
        lg.print("Tiny Hollow Knight–style Demo", W/2 - 160, H/2 - 28)
        lg.setFont(lg.newFont(14))
        lg.print("Controls: ← → to move • Z to jump • X to attack • C to dash", W/2 - 220, H/2 + 4)
        lg.print("Press Enter to start", W/2 - 80, H/2 + 44)
    elseif goal.reached then
        lg.setColor(0,0,0,0.5)
        lg.rectangle("fill", W/2 - 220, 60, 440, 84)
        lg.setColor(1,1,1)
        lg.setFont(lg.newFont(20))
        lg.print("Objective reached — short demo complete!", W/2 - 200, 100)
        lg.setFont(lg.newFont(14))
        lg.print("Feel free to press R to respawn and play again.", W/2 - 170, 130)
    end

    lg.setColor(0.62,0.69,0.78)
    lg.setFont(lg.newFont(12))
    lg.print("Open-source demo: single-file Love2D (main.lua)", W/2 - 110, H - 18)
end