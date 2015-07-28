/*	
 *	============================================================================
 *	
 *	[TF2] Automatic Halloween Boss Spawner
 *	Alliedmodders: http://forums.alliedmods.net/member.php?u=87026
 *	Current Version: 4.0.2
 *
 *	This plugin is FREE and can be distributed to anyone.  
 *	If you have paid for this plugin, get your money back.
 *	
 *	Version Log:
 *	v.4.0.2
 *	- Combined and rewritten the HUD countdown timer and spawn timers
 *	- HUD Timer countdown is now customizable
 *	- Removed a bunch of useless code
 *	- Fixed a bunch of stack timer errors
 *	- Fixed issue with timer not counting down by 1 interval seconds
 *	- Fixed issue with 2+ bosses spawning the same time
 *	- Fixed issue with plugin not spawning anything at all
 * 	- Fixed Minimum players CVAR not working properly by breaking the plugin
 *	- Fixed issue with CVAR changing commands
 * 	- Renamed plugin to "Custom Boss Spawner"
 *	- Added commands to individually spawn bosses by user cursor
 *	- Added the ability to create custom  bosses
 *	- Custom  bosses allow ability to change health,scale,size,glow,model,weaponmodel, and more
 *	- Redone the whole spawning system core
 *	- Removed Valves default lifetime for Monoculus and Merasmus and implemented a custom one through this plugin
 *	- Reworked Skeleton health management
 *	============================================================================
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <morecolors>

#define PLUGIN_VERSION "4.0.2"
#define HEALTHBAR_MAX 255

new Handle:Version = 		INVALID_HANDLE;
new Handle:Mode = 			INVALID_HANDLE;
new Handle:Time = 			INVALID_HANDLE;
new Handle:MinPlayers = 	INVALID_HANDLE;
new Handle:TimerHandle = 	INVALID_HANDLE;
new Handle:BossTimer = 		INVALID_HANDLE;
new Handle:hudText = 		INVALID_HANDLE;

new const String:BossAttributes[124][10][PLATFORM_MAX_PATH];
//0 - Name
//1 - Model
//2 - Type
//3 - HP base
//4 - HP Scale
//5 - WeaponModel
//6 - Size
//7 - Glow
//8 - PosFix
//9 - Lifeline

new g_Time;
new index_boss = 0;
new bool:g_Enabled;
new bossEnt = -1;
new Float:g_pos[3];
new Float:k_pos[3];
new bossCounter;
new g_trackent = -1;
new g_healthBar = -1;
new max_boss;
new bool:ActiveTimer;
new SpawnEnt;
new bool:queueBoss;
new index_command;
new bool:s_rand;

public Plugin:myinfo =  {
	name = "[TF2] Automatic Halloween Boss Spawner",
	author = "Tak (chaosxk)",
	description = "Spawns a boss under a spawn time interval.",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
}

public OnPluginStart() {
	//Adjustable Cvars
	Version = CreateConVar("sm_boss_version", PLUGIN_VERSION, "Halloween Boss Spawner Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	Mode = CreateConVar("sm_boss_mode", "1", "What spawn mode should boss spawn? (0 - Random ; 1 - Ordered from HHH - Monoculus - Merasmus");
	Time = CreateConVar("sm_boss_interval", "300", "How many seconds until the next boss spawns?");
	MinPlayers = CreateConVar("sm_boss_minplayers", "12", "How many players are needed before enabling auto-spawning?");

	RegAdminCmd("sm_getcoords", GetCoords, ADMFLAG_GENERIC, "Get the Coordinates of your cursor.");
	RegAdminCmd("sm_forceboss", ForceSpawn, ADMFLAG_GENERIC, "Forces a boss to spawn");
	RegAdminCmd("sm_slayboss", SlayBoss, ADMFLAG_GENERIC, "Forces a boss to die");
	RegAdminCmd("sm_reloadbossconfig", ReloadConfig, ADMFLAG_GENERIC, "Reloads the map setting config");
	RegAdminCmd("sm_spawn", SpawnBossCommand, ADMFLAG_GENERIC, "Spawns a boss at the position the user is looking at.");

	//Event Hooks
	HookEvent("teamplay_round_start", RoundStart);
	HookEvent("pumpkin_lord_summoned", Horse_Summoned, EventHookMode_Pre);
	HookEvent("pumpkin_lord_killed", Horse_Killed, EventHookMode_Pre);
	HookEvent("merasmus_summoned", Merasmus_Summoned, EventHookMode_Pre);
	HookEvent("merasmus_killed", Merasmus_Killed, EventHookMode_Pre);
	HookEvent("eyeball_boss_summoned", Monoculus_Summoned, EventHookMode_Pre);
	HookEvent("eyeball_boss_killed", Monoculus_Killed, EventHookMode_Pre);
	HookEvent("merasmus_escape_warning", Merasmus_Leave, EventHookMode_Pre);
	HookEvent("eyeball_boss_escape_imminent", Monoculus_Leave, EventHookMode_Pre);

	//Convar Hooks
	HookConVarChange(Version, cvarChange);
	HookConVarChange(Time, cvarChange);
	HookConVarChange(MinPlayers, cvarChange);
	
	
	LoadTranslations("common.phrases");
	LoadTranslations("bossspawner.phrases");
	AutoExecConfig(true, "bossspawner");
}

public OnPluginEnd() {
	RemoveExistingBoss();
}

public OnConfigsExecuted() {
	SetupMapConfigs("bossspawner_maps.cfg");
	if(!g_Enabled) return;
	SetupBossConfigs("bossspawner_boss.cfg");
	FindHealthBar();
	PrecacheSound("ui/halloween_boss_summoned_fx.wav");
}

public RemoveBossLifeline(const String:command[], const String:execute[], duration) {
	new flags = GetCommandFlags(command); 
	SetCommandFlags(command, flags & ~FCVAR_CHEAT); 
	ServerCommand("%s %i", execute, duration);
	//SetCommandFlags(command, flags|FCVAR_CHEAT); 
}

public OnMapEnd() {
	RemoveExistingBoss();
	if(!g_Enabled) return;
	ClearTimer(TimerHandle);
}

public OnClientPostAdminCheck(client) {
	if(GetClientCount(true) == GetConVarInt(MinPlayers)) {
		if(bossCounter == 0) {
			ResetTimer();
		}
	}
}

public OnClientDisconnect(client) {
	if(GetClientCount(true) < GetConVarInt(MinPlayers)) {
		RemoveExistingBoss();
		ClearTimer(TimerHandle);
	}
}

public cvarChange(Handle:convar, String:oldValue[], String:newValue[]) {
	if(convar == Version) {
		SetConVarString(Version, newValue, false, false);
	}
	else if((convar == Time) || (convar == MinPlayers)) {
		if(GetClientCount(true) >= GetConVarInt(MinPlayers)) {
			if(bossCounter == 0) {
				ResetTimer();
			}
		}
		else {
			RemoveExistingBoss();
			ClearTimer(TimerHandle);
		}
	}
}

public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast) {
	bossCounter = 0;
	if(!g_Enabled) return Plugin_Continue;
	ClearTimer(TimerHandle);
	if(GetClientCount(true) >= GetConVarInt(MinPlayers)) {
		if(bossCounter == 0) {
			ResetTimer();
		}
	}
	return Plugin_Continue;
}

public Action:Horse_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Horse_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
	return Plugin_Handled;
}

public Action:Merasmus_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Merasmus_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
	return Plugin_Handled;
}

public Action:Monoculus_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Monoculus_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
	return Plugin_Handled;
}

public Action:Merasmus_Leave(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action:Monoculus_Leave(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	return Plugin_Handled;
}

public OnEntityDestroyed(ent) {
	if(g_Enabled) {
		if(IsValidEntity(ent) && ent > MaxClients) {
			decl String:classname[MAX_NAME_LENGTH];
			GetEntityClassname(ent, classname, sizeof(classname));
			if(ent == bossEnt) {
				bossEnt = -1;
				bossCounter = 0;
				if(bossCounter == 0) {
					CPrintToChatAll("%t", "Time", RoundFloat(GetConVarFloat(Time)));
					hudTimer();
				}
				ClearTimer(BossTimer);
			}
			if(ent == g_trackent) {
				g_trackent = FindEntityByClassname(-1, "merasmus");
				if (g_trackent == ent) {
					g_trackent = FindEntityByClassname(ent, "merasmus");
				}
					
				if (g_trackent > -1) {
					SDKHook(g_trackent, SDKHook_OnTakeDamagePost, OnBossDamaged);
				}
				UpdateBossHealth(g_trackent);
			}
		}
	}
}

public Action:ForceSpawn(client, args) {
	if(!g_Enabled) return Plugin_Handled;
	new String:arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(bossCounter == 0) {
		ClearTimer(TimerHandle);
		SpawnBoss();
	}
	else {
		CReplyToCommand(client, "%t", "Boss_Active");
	}
	return Plugin_Handled;
}

public Action:GetCoords(client, args) {
	if(!g_Enabled) return Plugin_Handled;
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		ReplyToCommand(client, "%t", "Error");
		return Plugin_Handled;
	}
	new Float:l_pos[3];
	GetClientAbsOrigin(client, l_pos);
	ReplyToCommand(client, "[Boss Spawner] Coords: %0.0f,%0.0f,%0.0f\n[Boss Spawner] Use those coordinates and place them in configs/bossspawner_maps.cfg", l_pos[0], l_pos[1], l_pos[2]);
	return Plugin_Handled;
}

public Action:SlayBoss(client, args) {
	if(!g_Enabled) return Plugin_Handled;
	new ent = -1;
	while((ent = FindEntityByClassname(ent, "headless_hatman")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
			CPrintToChatAll("%t", "Horseman_Slain");
		}
	}
	while((ent = FindEntityByClassname(ent, "eyeball_boss")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
			CPrintToChatAll("%t", "Eyeball_Slain");
		}
	}
	while((ent = FindEntityByClassname(ent, "merasmus")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
			CPrintToChatAll("%t", "Merasmus_Slain");
		}
	}
	while((ent = FindEntityByClassname(ent, "tf_zombie")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
			CPrintToChatAll("%t", "Skeleton_Slain");
		}
	}
	//OnEntityDestroyed(bossEnt);
	return Plugin_Handled;
}

public Action:ReloadConfig(client, args) {
	ClearTimer(TimerHandle);
	SetupMapConfigs("bossspawner_maps.cfg");
	if(g_Enabled) {
		SetupMapConfigs("bossspawner_boss.cfg");
		ReplyToCommand(client, "[Boss Spawner] Configs have been reloaded!");
	}
}

public Action:SpawnBossCommand(client, args) {
	if(!g_Enabled) return Plugin_Handled;
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		ReplyToCommand(client, "%t", "Error");
		return Plugin_Handled;
	}
	if(!SetTeleportEndPoint(client)) {
		ReplyToCommand(client, "[Boss] Could not find spawn point.");
		return Plugin_Handled;
	}
	if(args != 1) {
		ReplyToCommand(client, "[Boss] Format: sm_spawn <boss>");
		return Plugin_Handled;
	}
	k_pos[2] -= 10.0;
	decl String:arg[15];
	GetCmdArg(1, arg, sizeof(arg));
	new i;
	for(i = 0; i < max_boss; i++) {
		if(StrEqual(BossAttributes[i][0], arg)){
			break;
		}
	}
	if(i == max_boss) {
		ReplyToCommand(client, "[Boss] Error: Boss does not exist.");
		return Plugin_Handled;
	}
	index_command = i;
	ActiveTimer = false;
	CreateBoss(index_command);
	return Plugin_Handled;
}

SetTeleportEndPoint(client) {
	decl Float:vAngles[3];
	decl Float:vOrigin[3];
	decl Float:vBuffer[3];
	decl Float:vStart[3];
	decl Float:Distance;

	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);

	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceentFilterPlayer);

	if(TR_DidHit(trace)) {
		TR_GetEndPosition(vStart, trace);
		GetVectorDistance(vOrigin, vStart, false);
		Distance = -35.0;
		GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		k_pos[0] = vStart[0] + (vBuffer[0]*Distance);
		k_pos[1] = vStart[1] + (vBuffer[1]*Distance);
		k_pos[2] = vStart[2] + (vBuffer[2]*Distance);
	}
	else {
		CloseHandle(trace);
		return false;
	}

	CloseHandle(trace);
	return true;
}

public bool:TraceentFilterPlayer(ent, contentsMask) {
	return ent > GetMaxClients() || !ent;
}

//random or ordered spawn manager
SpawnBoss() {
	new mode = GetConVarInt(Mode);
	ActiveTimer = true;
	if(mode == 0) {
		s_rand = true;
		index_boss = GetRandomInt(0, max_boss-1);
		PrintToChatAll("%d", index_boss);
		CreateBoss(index_boss);
	}
	else if(mode == 1) {
		s_rand = false;
		CreateBoss(index_boss);
		index_boss++;
		if(index_boss > max_boss-1) index_boss = 0;
	}
}

CreateBoss(b_index) {
	if(StrEqual(BossAttributes[b_index][2], "Horseman")) {
		new ent = CreateEntityByName("headless_hatman");
		if(IsValidEntity(ent)) {
			new playerCounter = GetClientCount(true);
			new BaseHP = StringToInt(BossAttributes[b_index][3]);
			new ScaleHP = StringToInt(BossAttributes[b_index][4]);
			SetEntProp(ent, Prop_Data, "m_iHealth", BaseHP + ScaleHP*playerCounter);
			SetEntProp(ent, Prop_Data, "m_iMaxHealth", BaseHP + ScaleHP*playerCounter);
			new Float:temp[3];
			temp = g_pos;
			temp[2] += StringToFloat(BossAttributes[b_index][8]);
			TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
			if(!StrEqual(BossAttributes[b_index][1], NULL_STRING)) {
				SetEntityModel(ent, BossAttributes[b_index][1]);
			}
			if(ActiveTimer == true) {
				bossCounter = 1;
				bossEnt = ent;
			}
			SetSize(StringToFloat(BossAttributes[b_index][6]), ent);
			SetGlow(StrEqual(BossAttributes[b_index][7], "Yes") ? 1 : 0, ent);
			BossTimer = CreateTimer(StringToFloat(BossAttributes[b_index][9]), RemoveBoss);
		}
	}
	else if(StrEqual(BossAttributes[b_index][2], "Monoculus")) {
		new ent = CreateEntityByName("eyeball_boss");
		if(IsValidEntity(ent)) {
			new playerCounter = GetClientCount(true);
			new BaseHP = StringToInt(BossAttributes[b_index][3]);
			new ScaleHP = StringToInt(BossAttributes[b_index][4]);
			SetEntProp(ent, Prop_Data, "m_iTeamNum", 5);
			SetEntProp(ent, Prop_Data, "m_iHealth", BaseHP + ScaleHP*playerCounter);
			SetEntProp(ent, Prop_Data, "m_iMaxHealth", BaseHP + ScaleHP*playerCounter);
			new Float:temp[3];
			temp = g_pos;
			temp[2] += StringToFloat(BossAttributes[b_index][8]);
			TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
			if(!StrEqual(BossAttributes[b_index][1], NULL_STRING)) {
				SetEntityModel(ent, BossAttributes[b_index][1]);
			}
			if(ActiveTimer == true) {
				bossCounter = 1;
				bossEnt = ent;
			}
			SetSize(StringToFloat(BossAttributes[b_index][6]), ent);
			SetGlow(StrEqual(BossAttributes[b_index][7], "Yes") ? 1 : 0, ent);
			BossTimer = CreateTimer(StringToFloat(BossAttributes[b_index][9]), RemoveBoss);
		}
	}
	else if(StrEqual(BossAttributes[b_index][2], "Merasmus")) {
		new ent = CreateEntityByName("merasmus");
		if(IsValidEntity(ent)) {
			new playerCounter = GetClientCount(true);
			new BaseHP = StringToInt(BossAttributes[b_index][3]);
			new ScaleHP = StringToInt(BossAttributes[b_index][4]);
			SetEntProp(ent, Prop_Data, "m_iTeamNum", 5);
			SetEntProp(ent, Prop_Data, "m_iHealth", BaseHP + ScaleHP*playerCounter);
			SetEntProp(ent, Prop_Data, "m_iMaxHealth", BaseHP + ScaleHP*playerCounter);
			new Float:temp[3];
			temp = g_pos;
			temp[2] += StringToFloat(BossAttributes[b_index][8]);
			TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
			if(!StrEqual(BossAttributes[b_index][1], NULL_STRING)) {
				SetEntityModel(ent, BossAttributes[b_index][1]);
			}
			if(ActiveTimer == true) {
				bossCounter = 1;
				bossEnt = ent;
			}
			SetSize(StringToFloat(BossAttributes[b_index][6]), ent);
			SetGlow(StrEqual(BossAttributes[b_index][7], "Yes") ? 1 : 0, ent);
			BossTimer = CreateTimer(StringToFloat(BossAttributes[b_index][9]), RemoveBoss);
		}
	}
	else if(StrEqual(BossAttributes[b_index][2], "Skeleton")) {
		new ent = CreateEntityByName("tf_zombie_spawner");
		if(IsValidEntity(ent)) {
			SetEntProp(ent, Prop_Data, "m_nSkeletonType", 1);
			new Float:temp[3];
			temp = g_pos;
			temp[2] += StringToFloat(BossAttributes[b_index][8]);
			TeleportEntity(ent, g_pos, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
			EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
			SpawnEnt = ent;
			queueBoss = true;
			AcceptEntityInput(ent, "Enable");
		}
	}
}

public Action:RemoveBoss(Handle:hTimer) {
	if(IsValidEntity(bossEnt)) {
		AcceptEntityInput(bossEnt, "Kill");
		CPrintToChatAll("%t", "Horseman_Left");
	}
	return Plugin_Handled;
}


SetGlow(value, ent) {
	if(IsValidEntity(ent)) {
		SetEntProp(ent, Prop_Send, "m_bGlowEnabled", value);
	}
}

SetSize(Float:value, ent) {
	if(IsValidEntity(ent)) {
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", value);
	}
}

ResetTimer() {
	if(bossCounter == 0) {
		CPrintToChatAll("%t", "Time", RoundFloat(GetConVarFloat(Time)));
		ClearTimer(TimerHandle);
		hudTimer();
	}
}

public hudTimer() {
	if(!g_Enabled) return;
	g_Time = GetConVarInt(Time);
	if(hudText != INVALID_HANDLE) {
		for(new i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i))
				ClearSyncHud(i, hudText);
		}
		CloseHandle(hudText);
	}
	hudText = CreateHudSynchronizer();
	SetHudTextParams(0.05, 0.05, 1.0, 255, 255, 255, 255);
	TimerHandle = CreateTimer(1.0, HUDCountDown, _, TIMER_REPEAT);
}

public Action:HUDCountDown(Handle:hTimer) {
	g_Time--;
	for(new i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			ShowSyncHudText(i, hudText, "Boss: %d seconds", g_Time);
		}
	}
	if(g_Time <= 0) {
		SpawnBoss();
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

//remove existing boss that has the same targetname so that it doesn't cause an extra spawn point
RemoveExistingBoss() {
	if(IsValidEntity(bossEnt)) {
		AcceptEntityInput(bossEnt, "kill");
		bossCounter = 0;
	}
}

FindHealthBar() {
	g_healthBar = FindEntityByClassname(-1, "monster_resource");
	if(g_healthBar == -1) {
		g_healthBar = CreateEntityByName("monster_resource");
		if(g_healthBar != -1) {
			DispatchSpawn(g_healthBar);
		}
	}
}

public OnEntityCreated(ent, const String:classname[]) {
	if (StrEqual(classname, "monster_resource")) {
		g_healthBar = ent;
	}
	else if(g_trackent == -1 && (StrEqual(classname, "headless_hatman") || StrEqual(classname, "merasmus") || StrEqual(classname, "headless_hatman"))) {
		g_trackent = ent;
		SDKHook(ent, SDKHook_SpawnPost, UpdateBossHealth);
		SDKHook(ent, SDKHook_OnTakeDamage, OnBossDamaged);
	}
	if(StrEqual(classname, "tf_zombie") && queueBoss == true) {
		g_trackent = ent;
		RequestFrame(OnSkeletonSpawn, EntIndexToEntRef(ent));
		SDKHook(ent, SDKHook_SpawnPost, UpdateBossHealth);
		SDKHook(ent, SDKHook_OnTakeDamage, OnBossDamaged);
	}
	if(StrEqual(classname, "prop_dynamic")) {
		RequestFrame(OnPropSpawn, EntIndexToEntRef(ent));
	}
}

public OnSkeletonSpawn(any:ref) {
	new ent = EntRefToEntIndex(ref);
	if(IsValidEntity(ent)) {
		new temp_index = index_boss;
		if(ActiveTimer == false) temp_index = index_command;
		else {
			if(s_rand == false) temp_index = index_boss == 0 ? max_boss-1 : index_boss-1;
			else temp_index = index_boss;
		}
		new playerCounter = GetClientCount(true);
		new BaseHP = StringToInt(BossAttributes[temp_index][3]);
		new ScaleHP = StringToInt(BossAttributes[temp_index][4]);
		SetEntProp(ent, Prop_Data, "m_iHealth", BaseHP + ScaleHP*playerCounter);
		SetEntProp(ent, Prop_Data, "m_iMaxHealth", BaseHP + ScaleHP*playerCounter);
		if(ActiveTimer == true) {
			bossCounter = 1;
			bossEnt = ent;
		}
		AcceptEntityInput(SpawnEnt, "kill");
		BossTimer = CreateTimer(StringToFloat(BossAttributes[temp_index][9]), RemoveBoss);
		CPrintToChatAll("%t", "Skeleton_Spawn");
		UpdateSkeleton(ent, temp_index);
		queueBoss = false;
	}
}

//Taken from SoulSharD
public OnPropSpawn(any:ref) {
	new ent = EntRefToEntIndex(ref);
	if(IsValidEntity(ent)) {
		new parent = GetEntPropEnt(ent, Prop_Data, "m_pParent");
		if(IsValidEntity(parent)) {
			decl String:strClassname[64];
			GetEntityClassname(parent, strClassname, sizeof(strClassname));
			if(StrEqual(strClassname, "headless_hatman", false))
			{
				new temp_index = index_boss;
				if(ActiveTimer == false) temp_index = index_command;
				else {
					if(s_rand == false) temp_index = index_boss == 0 ? max_boss-1 : index_boss-1;
					else temp_index = index_boss;
				}
				if(!StrEqual(BossAttributes[temp_index][5], NULL_STRING)){
					if(StrEqual(BossAttributes[temp_index][5], "Invisible")) {
						SetEntityModel(ent, "");
					}
					else {
						SetEntityModel(ent, BossAttributes[temp_index][5]);
						SetEntPropEnt(parent, Prop_Send, "m_hActiveWeapon", ent);
					}
				}
			}
		}
	}
}

UpdateSkeleton(ent, temp_index) {
	if(IsValidEntity(ent)) {
		SetSize(StringToFloat(BossAttributes[temp_index][6]), ent);
		SetGlow(StrEqual(BossAttributes[temp_index][7], "Yes") ? 1 : 0, ent);
	}
}  

public Action:OnBossDamaged(victim, &attacker, &inflictor, &Float:damage, &damagetype) {
	UpdateBossHealth(victim);
	UpdateDeathEvent(victim);
}

public UpdateDeathEvent(ent) {
	if(IsValidEntity(ent)) {
		new maxHP = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
		new HP = GetEntProp(ent, Prop_Data, "m_iHealth");
		if(HP <= (maxHP * 0.75)) {
			SetEntProp(ent, Prop_Data, "m_iHealth", 0);
			if(HP <= -1) {
				SetEntProp(ent, Prop_Data, "m_takedamage", 0);
			}
		}
	}
}

public UpdateBossHealth(ent) {
	if(g_healthBar == -1) {
		return;
	}
	new percentage;
	if(IsValidEntity(ent)) {
		new maxHP = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
		new HP = GetEntProp(ent, Prop_Data, "m_iHealth");
		if(HP <= 0) {
			percentage = 0;
		}
		else {
			percentage = RoundToCeil((float(HP) / float(maxHP / 4)) * 255);
		}
	}
	else {
		percentage = 0;
	}	
	SetEntProp(g_healthBar, Prop_Send, "m_iBossHealthPercentageByte", percentage);
}

public ClearTimer(&Handle:timer) {  
	if(timer != INVALID_HANDLE) {  
		KillTimer(timer);  
	}  
	timer = INVALID_HANDLE;  
}  

public SetupMapConfigs(const String:sFile[]) {
	new String:sPath[PLATFORM_MAX_PATH]; 
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss Spawner] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss Spawner] Error: Can not find map filepath %s", sPath);
	}
	new Handle:kv = CreateKeyValues("Boss Spawner Map");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) SetFailState("Could not read maps file: %s", sPath);
	
	new mapEnabled = 0;
	new bool:Default = false;
	new tempEnabled = 0;
	new Float:temp_pos[3];
	decl String:requestMap[PLATFORM_MAX_PATH];
	decl String:currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));
	do {
		KvGetSectionName(kv, requestMap, sizeof(requestMap));
		if(StrEqual(requestMap, currentMap, false)) {
			mapEnabled = KvGetNum(kv, "Enabled", 0);
			g_pos[0] = KvGetFloat(kv, "Position X", 0.0);
			g_pos[1] = KvGetFloat(kv, "Position Y", 0.0);
			g_pos[2] = KvGetFloat(kv, "Position Z", 0.0);
			Default = true;
		}
		else if(StrEqual(requestMap, "Default", false)) {
			tempEnabled = KvGetNum(kv, "Enabled", 0);
			temp_pos[0] = KvGetFloat(kv, "Position X", 0.0);
			temp_pos[1] = KvGetFloat(kv, "Position Y", 0.0);
			temp_pos[2] = KvGetFloat(kv, "Position Z", 0.0);
		}
	} while (KvGotoNextKey(kv));
	CloseHandle(kv);
	if(Default == false) {
		mapEnabled = tempEnabled;
		g_pos = temp_pos;
	}
	LogMessage("Map: %s, Enabled: %s, Position:%f, %f, %f", currentMap, mapEnabled ? "Yes" : "No", g_pos[0],g_pos[1],g_pos[2]);
	if(mapEnabled != 0) {
		g_Enabled = true;
		if(GetClientCount(true) >= GetConVarInt(MinPlayers)) {
			CPrintToChatAll("%t", "Time", RoundFloat(GetConVarFloat(Time)));
			hudTimer();
		}
	}
	else if(mapEnabled == 0) {
		g_Enabled = false;
	}
	LogMessage("Loaded Map configs successfully."); 
}

public SetupBossConfigs(const String:sFile[]) {
	new String:sPath[PLATFORM_MAX_PATH]; 
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss Spawner] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss Spawner] Error: Can not find map filepath %s", sPath);
	}
	new Handle:kv = CreateKeyValues("Custom Boss Spawner");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) SetFailState("Could not read maps file: %s", sPath);
	new b_index = 0;
	do {
		KvGetSectionName(kv, BossAttributes[b_index][0], sizeof(BossAttributes[][]));
		KvGetString(kv, "Model", BossAttributes[b_index][1], sizeof(BossAttributes[][]), NULL_STRING);
		KvGetString(kv, "Type", BossAttributes[b_index][2], sizeof(BossAttributes[][]));
		KvGetString(kv, "HP Base", BossAttributes[b_index][3], sizeof(BossAttributes[][]), "10000");
		KvGetString(kv, "HP Scale", BossAttributes[b_index][4], sizeof(BossAttributes[][]), "1000");
		KvGetString(kv, "WeaponModel", BossAttributes[b_index][5], sizeof(BossAttributes[][]), NULL_STRING);
		KvGetString(kv, "Size", BossAttributes[b_index][6], sizeof(BossAttributes[][]), "1.0");
		KvGetString(kv, "Glow", BossAttributes[b_index][7], sizeof(BossAttributes[][]), "Yes");
		KvGetString(kv, "PosFix", BossAttributes[b_index][8], sizeof(BossAttributes[][]), "0.0");
		KvGetString(kv, "Lifetime", BossAttributes[b_index][9], sizeof(BossAttributes[][]), "120");
		if(StrEqual(BossAttributes[b_index][2], "Skeleton") && !StrEqual(BossAttributes[b_index][1], NULL_STRING)) {
			if(StrEqual(BossAttributes[b_index][2], "Skeleton")) {
				LogError("Skeleton type is not supported.");
				SetFailState("Skeleton type is not supported.");
			}
		}
		if(!StrEqual(BossAttributes[b_index][2], "Horseman") && !StrEqual(BossAttributes[b_index][2], "Monoculus") && !StrEqual(BossAttributes[b_index][2], "Merasmus") && !StrEqual(BossAttributes[b_index][2], "Skeleton")){
			LogError("Type is undetermined, please check boss type again.");
			SetFailState("Type is undetermined, please check boss type again.");
		}
		if(StrEqual(BossAttributes[b_index][2], "Monoculus")) {
			RemoveBossLifeline("tf_eyeball_boss_lifetime", "tf_eyeball_boss_lifetime", StringToInt(BossAttributes[b_index][9])+1);
		}
		else if(StrEqual(BossAttributes[b_index][2], "Merasmus")) {
			RemoveBossLifeline("tf_merasmus_lifetime", "tf_merasmus_lifetime", StringToInt(BossAttributes[b_index][9])+1);
		}
		if(!StrEqual(BossAttributes[b_index][1], NULL_STRING)) {
			PrecacheModel(BossAttributes[b_index][1], true);
		}
		if(!StrEqual(BossAttributes[b_index][2], "Horseman")) {
			if(!StrEqual(BossAttributes[b_index][5], NULL_STRING)) {
				LogError("Weapon model can only be changed on Type:Horseman");
				SetFailState("Weapon model can only be changed on Type:Horseman");
			}
		}
		else if(!StrEqual(BossAttributes[b_index][5], NULL_STRING)) {
			if(!StrEqual(BossAttributes[b_index][5], "Invisible")) {
				PrecacheModel(BossAttributes[b_index][5], true);
			}
		}
		b_index++;
	} while (KvGotoNextKey(kv));
	max_boss = b_index;
	CloseHandle(kv);
	LogMessage("Loaded Boss configs successfully."); 
}
