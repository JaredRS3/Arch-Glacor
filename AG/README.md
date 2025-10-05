# Arch-Glacor Combat Script

A comprehensive combat automation script for fighting Arch-Glacor in RuneScape 3, supporting multiple enrage levels and combat styles.

## Features

- **Multi-Enrage Support**: Separate configurations for Low (<2500%), Standard, and High (2500%+) enrage
- **Intelligent Rotation Management**: Automated ability rotations with conditional logic
- **Dynamic Prayer Flicking**: Automatic prayer switching based on boss mechanics
- **Buff Management**: Automatic potion/buff maintenance including overloads, incense, and weapon poison
- **Health & Prayer Management**: Smart food/potion consumption with configurable thresholds
- **Boss Mechanic Handling**:
  - Arms/Exposed Core phases
  - Minion management with positioning
  - Pillars of Ice detection
  - Flurry phases
  - Frost Cannon mechanics

## Installation

1. Ensure you have the MemoryError client properly installed
2. Place the script files in your `Lua_Scripts` directory:
   ```
   Lua_Scripts/
   ├── Arch-Glacor
   ```
3. Ensure `api.lua` is present in the parent directory

## Configuration

### User Settings (config.lua)

```lua
Config.UserInput = {
    -- Banking
    useBankPin = false,
    bankPin = 1234,

    -- Keybinds
    targetCycleKey = 0x09,  -- Tab key

    -- Health thresholds
    healthThreshold = {
        normal = {type = "percent", value = 50},
        critical = {type = "percent", value = 25},
        special = {type = "percent", value = 75}  -- Excalibur
    },

    -- Prayer thresholds
    prayerThreshold = {
        normal = {type = "current", value = 200},
        critical = {type = "percent", value = 10},
        special = {type = "current", value = 600}  -- Elven shard
    },

    -- Preset checks
    presetChecks = {
        {id = 48951, amount = 10},  -- Vuln bombs
        {id = 42267, amount = 8},   -- Blue blubbers
    }
}
```

### Buff Configuration

The script automatically manages these buffs:

- **Elder Overload**: Maintains overload buff
- **Weapon Poison+++**: Keeps poison active
- **Incense Sticks**: Smart potency management (max level 4)
- **Powder of Penance**: Prayer restoration buff
- **Scripture of Jas/Ful**: Pocket slot activation
- **Familiar Contracts**: Ripper demon/Hellhound summoning

### Rotation Customization

Edit rotation tables in `config.lua`:

```lua
Config.RotationManager = {
    fightRotation = {
        name = "Fight Rotation",
        rotation = {
            {label = "Ability Name", wait = 3, useTicks = true},
            {label = "Conditional Ability",
             condition = function() return API.GetAdrenalineFromInterface() > 60 end,
             replacementLabel = "Alternative"}
        }
    }
}
```

## Usage

### Basic Commands

- **Start Script**: Run through client's Lua interface
- **Stop Script**: Press stop button or script terminates automatically
- **Emergency Teleport**: Script auto-teleports to War's Retreat when critical

### Script Usage

This script is optimized for hardmode Arch-Glacor:
- **Consistent Performance**: Works reliably from 0% to 3000% enrage
- **Balanced Approach**: Optimized rotations for all enrage levels
- **Smart Adaptation**: Automatically adjusts to boss mechanics

## Dependencies

### Required Files
- `core/player_manager.lua` - Health/prayer/buff management
- `core/rotation_manager.lua` - Ability rotation execution
- `core/prayer_flicker.lua` - Prayer switching system
- `core/timer.lua` - Timing utilities
- `api.lua` - Game API interface

### Required Items
- Enhanced Excalibur (augmented supported)
- Elven Ritual Shard (optional)
- Vulnerability bombs
- Food (Blue blubbers, Sailfish, etc.)
- Prayer potions/restores
- Elder overload potions

## Advanced Features

### Intelligent Incense Management

The script intelligently manages incense stick potency:
- Reads current potency from buff text
- Only increases potency when below level 4
- Extends duration when potency is maxed
- Refreshes when below 11 minutes remaining

### Combat Features

Script includes:
- Intelligent positioning algorithms
- Minion detection and targeting
- Dynamic movement based on mechanics
- Adaptive combat positioning

### Safety Features

Multiple safety mechanisms:
- Automatic food consumption at health thresholds
- One-tick eating for emergency situations
- Auto-teleport when out of supplies
- Excalibur activation at special threshold

## Troubleshooting

### Common Issues

1. **Script not drinking potions**
   - Verify potions are in inventory
   - Check buff configuration in `config.lua`
   - Ensure correct item IDs

2. **Rotation not executing**
   - Check ability names match exactly
   - Verify abilities are on action bar
   - Review condition functions

3. **Prayer flicker not working**
   - Confirm prayer book is correct
   - Check animation IDs for boss attacks
   - Verify prayer configuration

### Debug Mode

Enable debug output:
```lua
Utils.debug = true  -- In utils.lua
```

## API Changes

This script has been updated for the latest API:
- `Inventory:GetItemAmount()` for item counting
- `Inventory:Contains()` for item checks
- `Inventory:GetItems()` for inventory scanning
- `Equipment:GetOffhand()` for equipment checks


*Note: This script is designed for educational and accessibility purposes. Always follow game rules and terms of service.*
