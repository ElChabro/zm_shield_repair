#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_equipment;

init()
{
    level.shield_bench_stubs = [];
    level thread hook_shield_stub();
    level thread watch_carpenter_by_flag();
    level thread watch_players_shield_repair();
}

// ==========================================
// WORKBENCH REPAIR LOGIC
// ==========================================

hook_shield_stub()
{
    level endon("end_game");
    
    while(true)
    {
        if(isdefined(level._unitriggers) && isdefined(level._unitriggers.trigger_stubs))
        {
            foreach(stub in level._unitriggers.trigger_stubs)
            {
                if(!isdefined(stub.custom_repair_hooked) && is_shield_stub(stub))
                {
                    stub.custom_repair_hooked = true;
                    stub.old_prompt_func = stub.prompt_and_visibility_func;
                    stub.prompt_and_visibility_func = ::custom_shield_prompt;
                    
                    level.shield_bench_stubs[level.shield_bench_stubs.size] = stub;
                }
            }
        }
        wait 1;
    }
}

is_shield_stub(stub)
{
    if(isdefined(stub.equipname) && issubstr(stub.equipname, "shield")) return true;
    if(isdefined(stub.weaponname) && issubstr(stub.weaponname, "shield")) return true;
    if(isdefined(stub.craftable_name) && issubstr(stub.craftable_name, "shield")) return true;
    
    if(isdefined(stub.craftablespawn) && isdefined(stub.craftablespawn.craftable_name) && issubstr(stub.craftablespawn.craftable_name, "shield"))
    {
        return true;
    }
    
    return false;
}

player_shield_needs_repair(player)
{
    // 1. Vanilla BO2 _zm_weap_riotshield.gsc variable (no underscores!)
    if(isdefined(player.shielddamagetaken))
    {
        return (player.shielddamagetaken > 0);
    }

    // 2. Fallback in case a custom script uses underscores
    if(isdefined(player.shield_damage_taken))
    {
        return (player.shield_damage_taken > 0);
    }

    // 3. If neither variable is defined yet, allow repair so it never gets stuck
    return true;
}

custom_shield_prompt(player)
{
    // 1. Run the original prompt function FIRST
    can_see = false;
    if(isdefined(self.stub.old_prompt_func))
    {
        can_see = self [[self.stub.old_prompt_func]](player);
    }

    // 2. Override with the repair prompt if the player holds a shield and the bench is built
    shield_weapon = player get_player_shield();
    
    if(shield_weapon != "" && isdefined(self.stub.equipname))
    {
        if(player_shield_needs_repair(player))
        {
            self SetHintString("Hold ^3[{+activate}]^7 to repair Shield");
            return true;
        }
    }

    return can_see;
}

// Independent 20Hz loop that checks when the player presses F near the workbench
watch_players_shield_repair()
{
    level endon("end_game");

    while(true)
    {
        if(isdefined(level.players))
        {
            foreach(player in level.players)
            {
                if(is_player_valid(player) && player UseButtonPressed())
                {
                    if(!isdefined(player.is_repairing_shield) || !player.is_repairing_shield)
                    {
                        shield_weapon = player get_player_shield();
                        if(shield_weapon != "" && player_shield_needs_repair(player))
                        {
                            if(player is_near_built_shield_bench())
                            {
                                player thread do_shield_repair_from_prompt(shield_weapon);
                            }
                        }
                    }
                }
            }
        }
        wait 0.05;
    }
}

is_near_built_shield_bench()
{
    if(!isdefined(level.shield_bench_stubs))
        return false;

    foreach(stub in level.shield_bench_stubs)
    {
        if(isdefined(stub) && isdefined(stub.equipname))
        {
            // Check stub.origin (or stub.craftablespawn.origin on Origins/Tranzit)
            bench_origin = stub.origin;
            if(!isdefined(bench_origin) && isdefined(stub.craftablespawn))
            {
                bench_origin = stub.craftablespawn.origin;
            }

            if(isdefined(bench_origin) && Distance(self.origin, bench_origin) <= 120)
            {
                return true;
            }
        }
    }
    return false;
}

do_shield_repair_from_prompt(shield_weapon)
{
    self endon("disconnect");
    
    self.is_repairing_shield = true;
    
    self repair_player_shield(shield_weapon);
    
    self iprintln("^2Shield Repaired");
    self playlocalsound("evt_carpenter");
    
    // Refresh the workbench prompt so it changes back to "Already have one"
    foreach(stub in level.shield_bench_stubs)
    {
        if(isdefined(stub))
        {
            maps\mp\zombies\_zm_unitrigger::unregister_unitrigger(stub);
            maps\mp\zombies\_zm_unitrigger::register_static_unitrigger(stub, stub.trigger_func);
        }
    }
    
    wait 1;
    self.is_repairing_shield = false;
}

// ==========================================
// CARPENTER REPAIR LOGIC
// ==========================================

watch_carpenter_by_flag()
{
    level endon("end_game");
    was_active = false;
    
    while(true)
    {
        is_active = (isdefined(level.carpenter_powerup_active) && level.carpenter_powerup_active);
        
        if(is_active && !was_active)
        {
            foreach(player in level.players)
            {
                shield_weapon = player get_player_shield();
                if(shield_weapon != "")
                {
                    player thread repair_player_shield(shield_weapon);
                    player iprintln("^2Shield Repaired by Carpenter!");
                }
            }
        }
        
        was_active = is_active;
        wait 0.1;
    }
}

// ==========================================
// UTILITY FUNCTIONS
// ==========================================

get_player_shield()
{
    weapons = self GetWeaponsList();
    foreach(weapon in weapons)
    {
        if(issubstr(weapon, "shield"))
        {
            return weapon;
        }
    }
    return "";
}

repair_player_shield(shield_weapon)
{
    // Reset BO2's native shielddamagetaken (no underscores) AND custom shield_damage_taken
    self.shielddamagetaken = 0;
    self.shield_damage_taken = 0;
    
    if(isdefined(self.player_shield_reset_health))
    {
        self [[self.player_shield_reset_health]]();
    }
    else if(isdefined(level.zombiemode_equipment) && isdefined(level.zombiemode_equipment[shield_weapon]))
    {
        self maps\mp\zombies\_zm_equipment::equipment_take(shield_weapon);
        self maps\mp\zombies\_zm_equipment::equipment_give(shield_weapon);
    }
    else
    {
        self TakeWeapon(shield_weapon);
        self GiveWeapon(shield_weapon);
        self setWeaponAmmoClip(shield_weapon, 1);
    }
}