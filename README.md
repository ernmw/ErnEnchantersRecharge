# ErnEnchantersRecharge

OpenMW mod that adds an item recharging service to all Enchanters.

## Installing

Download the [latest version here](https://github.com/erinpentecost/ErnEnchantersRecharge/archive/refs/heads/main.zip).

Extract to your `mods/` folder. In your `openmw.cfg` file, add these lines in the correct spots:

```ini
data="/wherevermymodsare/mods/ErnEnchantersRecharge-main"
content=ErnEnchantersRecharge.omwscripts
content=ErnEnchantersRecharge.omwaddon
```

Optionally add this line to disable natural enchanted item recharging:

```ini
content=ErnDisableNaturalRecharge.omwaddon
```


## Patching

You can set `fMagicItemChargeRechargeMult` to change the recharge cost.
