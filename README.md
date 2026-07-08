# BioWars MVP

A small Godot 4 prototype for a turn-based tactics game set inside a human body. The current slice focuses on the core hook: two simultaneous battles where one battlefield can alter the other.

## Current Playable Loop

- Two active isometric battlefields: Lungs and Bloodstream.
- The screen is split into quadrants: main battle upper-left, secondary battle lower-left, host PIP/stats upper-right, and a reserved third battlefield lower-right.
- Infection units can move one tile or bite adjacent immune cells.
- Immune cells respond after the player ends the turn.
- Cough Burst is charged over turns and requires a germ in the lungs.
- Cough Burst pushes units across the lungs, can expel edge units, shakes the live host picture-in-picture, lowers oxygen, and queues a germ reinforcement in the bloodstream.
- The run is won when all immune cells are defeated and lost when all germs are cleared.

## Controls

- Click a green germ to select it.
- Click an adjacent empty tile to move.
- Click an adjacent immune cell to attack.
- Use End Turn to let immune cells act.
- Use Cough Burst once it reaches 3/3 charge.
- Use Reset Run to restart the MVP scenario.

## Current Art Assets

- `assets/backgrounds/lungs_battlefield.png`: pixel art lungs battlefield.
- `assets/backgrounds/bloodstream_battlefield.png`: pixel art bloodstream battlefield.
- `assets/sprites/host_sickness_sheet.png`: host PIP sickness and cough frames.

## Next MVP Steps

- Add a real overworld body map for choosing organs.
- Give each battlefield a unique rule package.
- Add forecasted enemy actions in an Into the Breach style.
- Replace code-drawn placeholders with pixel art sprites.
- Add roguelike run upgrades, pathogens, and host traits.
