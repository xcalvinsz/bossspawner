/*	
 *	============================================================================
 *	
 *	[TF2] Custom Boss Spawner
 *	Alliedmodders: https://forums.alliedmods.net/showthread.php?t=218119
 *	Current Version: 4.3.1
 *
 *	Written by Tak (Chaosxk)
 *	https://forums.alliedmods.net/member.php?u=87026
 *
 *	This plugin is FREE and can be distributed to anyone.  
 *	If you have paid for this plugin, get your money back.
 *	
Version Log:
v.4.4 -
	- Saved data information with datapack instead of m_iname in the entity itself
	- Changed and updated some more functions to be more object oriented
	- Fixed some healthbar issue with multiple bosses
	- Fixed a small issue with reloading add/remove commands
v.4.3.1 -
	- Fixed sm_reloadbossconfigs causing console-spawned bosses to spawn more than one depending on how many times you reloaded or map changes
	- Fixed the built-in downloader for this plugin having directory problems with linux file system
	- Fixed a small memory leak with the download handles
	- Fixed a bug where all bosses would be killed off if one of the bosses remove timer was triggered
	- Fixed a bug where the remove timer would overlap to the next spawned boss
	- Fixed a bug where DeathSound would not play if more than 1 boss was active
	- Fixed a bug where "horseman has left due to boredom" is printed on next boss
v 4.3 -
Added:
	- Bosses can now equip hats
	- Added new key: Gnome [0-Off : 1-On] [Restriction: tf_zombie] Spawns mini-gnome skeletons when skeleton/skeleton king dies
	- Added new HUD display over the healthbar to display exact value of boss health
	- sm_spawn command is replaced by !spawnboss and !sb, both opens a menu to spawn boss where the player looks at
	- Added override (sm_boss_override) to override boss spawn flag (!horseman, !monoculus, ... etc)
	- Added command !fb which does the same as !forceboss
	- Added value: "none" to key "IntroSound" and "DeathSound" which will not play any sound 
	- Added keys: "HatPosFix" and "HatSize" and "Damage" to bossspawner_boss.cfg
	- Added built-in downloader/precacher (bossspawner_downloads.cfg)
Changed:
	- Plugin has been changed to use the new API/Syntax
	- Bosses can now be spawned using !<bossname> <health> <size> <glow>
	- Skeleton King hitbox can now resize to scale
	- Changed the way the plugin keeps track of bosses index to be more readable/efficient
	- Bosses spawned by command will now run under a remove time (key: lifetime)
	- Plugin will now error out if there is a space in bosses name, replace spaces with _.
	- When boss spawn message is printed, it will replace _ in the name with a space. (E.G Name:The_Horseman -> The Horseman has spawned)
Removed:
	- sm_spawn command has been removed
	- tf_skeleton_spawner type has been removed, replaced with tf_zombie
Fixed:
	- Fixed issue with sm_reloadconfigs not reloading the configs properly
	- Fixed issue where boss death sound may play the wrong sound
	- Fixed issue where message will say boss has left although the boss already died
	- Fixed issue where tf_zombie would die from colliding with payload cart
	- Fixed issue with spawning 2 bosses and the healthbar not working for 2nd boss
Known Issues:
	- When tf_skeleton with a hat attacks you while standing still, his hat model may freeze until he starts moving
	- eyeball_boss can die from collision from a payload cart, most of time in air so it doesn't matter too much
	- Hat size and offset does not change if player manually spawns a boss with a different size from the config (e.g !horseman 1000 5 1 : Horseman size is 5 but default size in boss config is 1, if this boss has a hat the hat won't resize)
 *	============================================================================
 */
#pragma semicolon 1
#include <morecolors>
#include <sdktools>
#pragma newdecls required
#include <sourcemod>
#include <sdkhooks>

#define PLUGIN_VERSION "4.3.1"
#define INTRO_SND	"ui/halloween_boss_summoned_fx.wav"
#define DEATH_SND	"ui/halloween_boss_defeated_fx.wav"
#define HORSEMAN	"headless_hatman"
#define MONOCULUS	"eyeball_boss"
#define MERASMUS	"merasmus"
#define SKELETON	"tf_zombie"
#define SNULL 		""

ConVar cVars[6] = {null, ...};
Handle cTimer = null; //jHUD = null; //hHUD = null;
ArrayList gArray = null; //gHArray = null, gCArray = null;
ArrayList dataArray = null;

//Variables for ConVars conversion
int sMode;
float sInterval, sMin, sHUDx, sHUDy;
bool gEnabled;

//Other variables
int gIndex, gIndexCmd, gIsMultiSpawn;
float gPos[3], kPos[3];
bool gActiveTimer;
int gHCount, gCCount, gTrack = -1, gHPbar = -1;

//Index saving
int argIndex, saveIndex;

public Plugin myinfo =  {
	name = "[TF2] Custom Boss Spawner",
	author = "Tak (chaosxk)",
	description = "An advanced boss spawner.",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
}

public void OnPluginStart() {
	cVars[0] = CreateConVar("sm_boss_version", PLUGIN_VERSION, "Custom Boss Spawner Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cVars[1] = CreateConVar("sm_boss_mode", "1", "Spawn mode for auto-spawning [0:Random | 1:Ordered]");
	cVars[2] = CreateConVar("sm_boss_interval", "300", "How many seconds until the next boss spawns?");
	cVars[3] = CreateConVar("sm_boss_minplayers", "12", "How many players are needed before enabling auto-spawning?");
	cVars[4] = CreateConVar("sm_boss_hud_x", "0.05", "X-Coordinate of the HUD display.");
	cVars[5] = CreateConVar("sm_boss_hud_y", "0.05", "Y-Coordinate of the HUD display");

	RegAdminCmd("sm_getcoords", GetCoords, ADMFLAG_GENERIC, "Get the Coordinates of your cursor.");
	RegAdminCmd("sm_reloadbossconfig", ReloadConfig, ADMFLAG_GENERIC, "Reloads the boss configs.");
	RegAdminCmd("sm_forceboss", ForceBoss, ADMFLAG_GENERIC, "Forces a auto-spawning boss to spawn early.");
	RegAdminCmd("sm_fb", ForceBoss, ADMFLAG_GENERIC, "Forces a auto-spawning boss to spawn early.");
	RegAdminCmd("sm_spawnboss", SpawnMenu, ADMFLAG_GENERIC, "Opens a menu to spawn a boss.");
	RegAdminCmd("sm_sb", SpawnMenu, ADMFLAG_GENERIC, "Opens a menu to spawn a boss.");
	RegAdminCmd("sm_slayboss", SlayBoss, ADMFLAG_GENERIC, "Slay all active bosses on map.");
	
	//hHUD = CreateHudSynchronizer();
	//jHUD = CreateHudSynchronizer();
	
	HookEvent("teamplay_round_start", RoundStart);
	HookEvent("pumpkin_lord_summoned", Boss_Summoned, EventHookMode_Pre);
	HookEvent("pumpkin_lord_killed", Boss_Killed, EventHookMode_Pre);
	HookEvent("merasmus_summoned", Boss_Summoned, EventHookMode_Pre);
	HookEvent("merasmus_killed", Boss_Killed, EventHookMode_Pre);
	HookEvent("eyeball_boss_summoned", Boss_Summoned, EventHookMode_Pre);
	HookEvent("eyeball_boss_killed", Boss_Killed, EventHookMode_Pre);
	HookEvent("merasmus_escape_warning", Merasmus_Leave, EventHookMode_Pre);
	HookEvent("eyeball_boss_escape_imminent", Monoculus_Leave, EventHookMode_Pre);

	for(int i = 0; i < 6; i++)
		cVars[i].AddChangeHook(cVarChange);
	
	gArray = new ArrayList();
	//gHArray = new ArrayList();
	//gCArray = new ArrayList();
	dataArray = new ArrayList();
	
	LoadTranslations("common.phrases");
	LoadTranslations("bossspawner.phrases");
	AutoExecConfig(true, "bossspawner");
}

public void OnPluginEnd() {
	RemoveExistingBoss();
	ClearTimer(cTimer);
	//reset flags for cheat cmds lifetime
	int flags = GetCommandFlags("tf_eyeball_boss_lifetime");
	SetCommandFlags("tf_eyeball_boss_lifetime", flags|FCVAR_CHEAT);
	flags = GetCommandFlags("tf_merasmus_lifetime");
	SetCommandFlags("tf_merasmus_lifetime", flags|FCVAR_CHEAT);
}

public void OnConfigsExecuted() {
	sMode = GetConVarInt(cVars[1]);
	sInterval = GetConVarFloat(cVars[2]);
	sMin = GetConVarFloat(cVars[3]);
	sHUDx = GetConVarFloat(cVars[4]);
	sHUDy = GetConVarFloat(cVars[5]);
	SetupMapConfigs("bossspawner_maps.cfg");
	SetupBossConfigs("bossspawner_boss.cfg");
	SetupDownloads("bossspawner_downloads.cfg");
	if(gEnabled) {
		FindHealthBar();
		PrecacheSound("items/cart_explode.wav");
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i)) {
				SDKHook(i, SDKHook_OnTakeDamage, OnClientDamaged);
			}
		}
	}
}

public void RemoveBossLifeline(const char[] command, const char[] execute, int duration) {
	int flags = GetCommandFlags(command); 
	SetCommandFlags(command, flags & ~FCVAR_CHEAT); 
	ServerCommand("%s %d", execute, duration);
	//SetCommandFlags(command, flags|FCVAR_CHEAT); 
}

public void OnMapEnd() {
	RemoveExistingBoss();
	ClearTimer(cTimer);
}

public void OnClientPostAdminCheck(int client) {
	if(GetClientCount(true) == sMin) {
		if(gHCount == 0) {
			ResetTimer();
		}
	}
	SDKHook(client, SDKHook_OnTakeDamage, OnClientDamaged);
}

public void OnClientDisconnect(int client) {
	if(GetClientCount(true) < sMin) {
		RemoveExistingBoss();
		ClearTimer(cTimer);
	}
}

public void cVarChange(Handle convar, char[] oldValue, char[] newValue) {
	if (StrEqual(oldValue, newValue, true))
		return;
	
	float iNewValue = StringToFloat(newValue);

	if(convar == cVars[0])  {
		SetConVarString(cVars[0], PLUGIN_VERSION);
	}
	else if(convar == cVars[1]) {
		sMode = RoundFloat(iNewValue);
	}
	else if((convar == cVars[2]) || (convar == cVars[3])) {
		if(convar == cVars[2]) sInterval = iNewValue;
		else sMin = iNewValue;
		
		if(GetClientCount(true) >= sMin) {
			if(gHCount == 0) {
				ResetTimer();
			}
		}
		else {
			RemoveExistingBoss();
			ClearTimer(cTimer);
		}
	}
	else if(convar == cVars[4]) {
		sHUDx = iNewValue;
	}
	else if(convar == cVars[5]) {
		sHUDy = iNewValue;
	}
}

/* -----------------------------------EVENT HANDLES-----------------------------------*/
public Action RoundStart(Handle event, const char[] name, bool dontBroadcast) {
	gHCount = 0;
	if(!gEnabled) return Plugin_Continue;
	ClearTimer(cTimer);
	if(GetClientCount(true) >= sMin) {
		if(gHCount == 0) {
			ResetTimer();
		}
	}
	return Plugin_Continue;
}

public Action Boss_Summoned(Handle event, const char[] name, bool dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action Boss_Killed(Handle event, const char[] name, bool dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action Merasmus_Leave(Handle event, const char[] name, bool dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action Monoculus_Leave(Handle event, const char[] name, bool dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}
/* -----------------------------------EVENT HANDLES-----------------------------------*/

/* ---------------------------------COMMAND FUNCTION----------------------------------*/

public Action ForceBoss(int client, int args) {
	if(!gEnabled) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(gHCount == 0) {
		gActiveTimer = true;
		if(args == 1) {
			saveIndex = gIndex;
			char arg1[32];
			char sName[64];
			GetCmdArg(1, arg1, sizeof(arg1));
			int i;
			for(i = 0; i < gArray.Length; i++) {
				StringMap HashMap = gArray.Get(i);
				HashMap.GetString("Name", sName, sizeof(sName));
				if(StrEqual(sName, arg1, false)) {
					gIndex = i;
					break;
				}
			}
			if(i == gArray.Length) {
				CReplyToCommand(client, "{frozen}[Boss] {red}Error: {orange}Boss does not exist.");
				return Plugin_Handled;
			}
			ClearTimer(cTimer);
			argIndex = 1;
			CreateBoss(gIndex, gPos, -1, -1, -1.0, -1, false);
		}
		else if(args == 0) {
			argIndex = 0;
			ClearTimer(cTimer);
			SpawnBoss(-1,-1.0,-1);
		}
		else {
			CReplyToCommand(client, "{frozen}[Boss] {red}Format: {orange}!forceboss <bossname>");
		}
	}
	else {
		CReplyToCommand(client, "%t", "Boss_Active");
	}
	return Plugin_Handled;
}

public Action GetCoords(int client, int args) {
	if(!gEnabled) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CReplyToCommand(client, "{frozen}[Boss] You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	float l_pos[3];
	GetClientAbsOrigin(client, l_pos);
	CReplyToCommand(client, "{frozen}[Boss] {orange}Coordinates: %0.0f,%0.0f,%0.0f\n{frozen}[Boss] {orange}Use those coordinates and place them in configs/bossspawner_maps.cfg", l_pos[0], l_pos[1], l_pos[2]);
	return Plugin_Handled;
}

public Action SlayBoss(int client, int args) {
	if(!gEnabled) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	RemoveExistingBoss();
	CPrintToChatAll("%t", "Boss_Slain");
	return Plugin_Handled;
}

public Action ReloadConfig(int client, int args) {
	ClearTimer(cTimer);
	SetupMapConfigs("bossspawner_maps.cfg");
	SetupBossConfigs("bossspawner_boss.cfg");
	SetupDownloads("bossspawner_downloads.cfg");
	CReplyToCommand(client, "{frozen}[Boss] {orange}Configs have been reloaded!");
	return Plugin_Handled;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	char arg[4][64];
	int args = ExplodeString(sArgs, " ", arg, sizeof(arg), sizeof(arg[]));
	//int returnType = 0;
	if(arg[0][0] == '!' || arg[0][0] == '/') {
		//if(arg[0][0] == '/') returnType = 1;
		strcopy(arg[0], 64, arg[0][1]);
	}
	else return Plugin_Continue;
	int i;
	StringMap HashMap = null;
	char sName[64];
	for(i = 0; i < gArray.Length; i++) {
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		if(StrEqual(sName, arg[0], false)){
			break;
		}
	}
	if(i == gArray.Length) {
		return Plugin_Continue;
	}
	/*if(returnType == 0) {
		char name[64];
		GetClientName(client, name, sizeof(name));
		int team = GetClientTeam(client);
		if(StrEqual(command, "say")) {
			CPrintToChatAllEx(client, "{teamcolor}%s :  {default}%s", name, sArgs);
		}
		else if(StrEqual(command, "say_team")) {
			for(int j = 1; j <= MaxClients; j++) {
				int iTeam = GetClientTeam(j);
				if(team != iTeam) continue;
				CPrintToChatEx(j, client, "{default}(TEAM){teamcolor}%s :  {default}%s", name, sArgs);
			}
		}
	}*/
	if(!gEnabled) {
		CPrintToChat(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(!CheckCommandAccess(client, "sm_boss_override", ADMFLAG_GENERIC, false)) {
		CPrintToChat(client, "{frozen}[Boss] {orange}You do not have access to this command.");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CPrintToChat(client, "{frozen}[Boss] {orange}You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	if(!SetTeleportEndPoint(client)) {
		CPrintToChat(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
		return Plugin_Handled;
	}
	kPos[2] -= 10.0;
	int iBaseHP = -1, iGlow = -1;
	float iSize = -1.0;
	if(args > 1) {
		iBaseHP = StringToInt(arg[1]);
	}
	if(args > 2) {
		iSize = StringToFloat(arg[2]);
	}
	if(args > 3) {
		iGlow = StringToInt(arg[3]);
	}
	gIndexCmd = i;
	gActiveTimer = false;
	CreateBoss(gIndexCmd, kPos, iBaseHP, 0, iSize, iGlow, true);
	return Plugin_Handled;
}

public Action SpawnBossCommand(int client, const char[] command, int args) {
	char arg1[64], arg2[32], arg3[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	int i;
	StringMap HashMap = null;
	char sName[64];
	int nIndex = FindCharInString(command, '_', _) + 1;
	char command2[64];
	strcopy(command2, sizeof(command2), command[nIndex]);
	for(i = 0; i < gArray.Length; i++) {
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		if(StrEqual(sName, command2, false)){
			break;
		}
	}
	if(i == gArray.Length) {
		return Plugin_Continue;
	}
	if(!gEnabled) {
		CPrintToChat(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(!CheckCommandAccess(client, "sm_boss_override", ADMFLAG_GENERIC, false)) {
		CPrintToChat(client, "{frozen}[Boss] {orange}You do not have access to this command.");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CPrintToChat(client, "{frozen}[Boss] {orange}You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	if(!SetTeleportEndPoint(client)) {
		CPrintToChat(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
		return Plugin_Handled;
	}
	kPos[2] -= 10.0;
	int iBaseHP = -1, iGlow = -1;
	float iSize = -1.0;
	if(args > 0) {
		GetCmdArg(1, arg1, sizeof(arg1));
		iBaseHP = StringToInt(arg1);
	}
	if(args > 1) {
		GetCmdArg(2, arg2, sizeof(arg2));
		iSize = StringToFloat(arg2);
	}
	if(args > 2) {
		GetCmdArg(3, arg3, sizeof(arg3));
		iGlow = StringToInt(arg3);
	}
	gIndexCmd = i;
	gActiveTimer = false;
	CreateBoss(gIndexCmd, kPos, iBaseHP, 0, iSize, iGlow, true);
	return Plugin_Handled;
}

public Action SpawnMenu(int client, int args) {
	if(!gEnabled) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CReplyToCommand(client, "{frozen}[Boss] You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	ShowMenu(client);
	return Plugin_Handled;
}

public void ShowMenu(int client) {
	StringMap HashMap = null;
	char sName[64], sInfo[8];
	Menu menu = new Menu(DisplayHealth);
	SetMenuTitle(menu, "Boss Menu");
	for(int i = 0; i < gArray.Length; i++) {
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		IntToString(i, sInfo, sizeof(sInfo));
		menu.AddItem(sInfo, sName);
	}
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int DisplayHealth(Menu MenuHandle, MenuAction action, int client, int num) {
	if(action == MenuAction_Select) {
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(DisplaySizes);
		menu.SetTitle("Boss Health");
		char param[32];
		Format(param, sizeof(param), "%s 1000", info);
		menu.AddItem(param, "1000");
		Format(param, sizeof(param), "%s 5000", info);
		menu.AddItem(param, "5000");
		Format(param, sizeof(param), "%s 10000", info);
		menu.AddItem(param, "10000");
		Format(param, sizeof(param), "%s 15000", info);
		menu.AddItem(param, "15000");
		Format(param, sizeof(param), "%s 20000", info);
		menu.AddItem(param, "20000");
		Format(param, sizeof(param), "%s 30000", info);
		menu.AddItem(param, "30000");
		Format(param, sizeof(param), "%s 50000", info);
		menu.AddItem(param, "50000");
		SetMenuExitButton(menu, true);
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if(action == MenuAction_End) {
		delete MenuHandle;
	}
}

public int DisplaySizes(Menu MenuHandle, MenuAction action, int client, int num) {
	if(action == MenuAction_Select) {
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(DisplayGlow);
		menu.SetTitle("Boss Size");
		char param[32];
		Format(param, sizeof(param), "%s 0.5", info);
		menu.AddItem(param, "0.5");
		Format(param, sizeof(param), "%s 1.0", info);
		menu.AddItem(param, "1.0");
		Format(param, sizeof(param), "%s 1.5", info);
		menu.AddItem(param, "1.5");
		Format(param, sizeof(param), "%s 2.0", info);
		menu.AddItem(param, "2.0");
		Format(param, sizeof(param), "%s 3.0", info);
		menu.AddItem(param, "3.0");
		Format(param, sizeof(param), "%s 4.0", info);
		menu.AddItem(param, "4.0");
		Format(param, sizeof(param), "%s 5.0", info);
		menu.AddItem(param, "5.0");
		SetMenuExitButton(menu, true);
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if(action == MenuAction_End) {
		delete MenuHandle;
	}
}

public int DisplayGlow(Menu MenuHandle, MenuAction action, int client, int num) {
	if(action == MenuAction_Select) {
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(EndMenu);
		menu.SetTitle("Boss Glow");
		char param[32];
		Format(param, sizeof(param), "%s 1", info);
		menu.AddItem(param, "On");
		Format(param, sizeof(param), "%s 0", info);
		menu.AddItem(param, "Off");
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if(action == MenuAction_End) {
		delete MenuHandle;
	}
}

public int EndMenu(Menu MenuHandle, MenuAction action, int client, int num) {
	if(action == MenuAction_Select) {
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		char sAttribute[4][16];
		ExplodeString(info, " ", sAttribute, sizeof(sAttribute), sizeof(sAttribute[]));
		int iIndex, iBaseHP, iGlow;
		float iSize;
		iIndex = StringToInt(sAttribute[0]);
		iBaseHP = StringToInt(sAttribute[1]);
		iSize = StringToFloat(sAttribute[2]);
		iGlow = StringToInt(sAttribute[3]);
		if(!SetTeleportEndPoint(client)) {
			CReplyToCommand(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
			return;
		}
		kPos[2] -= 10.0;
		gActiveTimer = false;
		CreateBoss(iIndex, kPos, iBaseHP, 0, iSize, iGlow, true);
	}
	else if(action == MenuAction_End) {
		delete MenuHandle;
	}
}

bool SetTeleportEndPoint(int client) {
	float vAngles[3], vOrigin[3], vBuffer[3], vStart[3], Distance;

	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceentFilterPlayer);

	if(TR_DidHit(trace)) {
		TR_GetEndPosition(vStart, trace);
		GetVectorDistance(vOrigin, vStart, false);
		Distance = -35.0;
		GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		kPos[0] = vStart[0] + (vBuffer[0]*Distance);
		kPos[1] = vStart[1] + (vBuffer[1]*Distance);
		kPos[2] = vStart[2] + (vBuffer[2]*Distance);
	}
	else {
		delete trace;
		return false;
	}

	delete trace;
	return true;
}

public bool TraceentFilterPlayer(int ent, int contentsMask) {
	return ent > GetMaxClients() || !ent;
}
/* ---------------------------------COMMAND FUNCTION----------------------------------*/

/* --------------------------------BOSS SPAWNING CORE---------------------------------*/
void SpawnBoss(int iBaseHP, float iSize, int iGlow) {
	int iScaleHP;
	if(iBaseHP != -1) {
		iScaleHP = 0;
	}
	gActiveTimer = true;
	if(sMode == 0) {
		gIndex = GetRandomInt(0, gArray.Length-1);
		CreateBoss(gIndex, gPos, iBaseHP, iScaleHP, iSize, iGlow, false);
	}
	else if(sMode == 1) {
		CreateBoss(gIndex, gPos, iBaseHP, iScaleHP, iSize, iGlow, false);
	}
}

public void CreateBoss(int index, float kpos[3], int iBaseHP, int iScaleHP, float iSize, int iGlow, bool isCMD) {
	float temp[3];
	for(int i = 0; i < 3; i++)
		temp[i] = kpos[i];
	
	char sName[64], sModel[256], sType[32], sBase[16], sScale[16], sSize[16], sGlow[8], sPosFix[32];
	char sLifetime[32], sPosition[32], sHorde[8], sColor[16], sHModel[256], sISound[256], sHatPosFix[32], sHatSize[16];

	StringMap HashMap = gArray.Get(index);
	HashMap.GetString("Name", sName, sizeof(sName));
	HashMap.GetString("Model", sModel, sizeof(sModel));
	HashMap.GetString("Type", sType, sizeof(sType));
	HashMap.GetString("PosFix", sPosFix, sizeof(sPosFix));
	HashMap.GetString("Lifetime", sLifetime, sizeof(sLifetime));
	HashMap.GetString("Position", sPosition, sizeof(sPosition));
	HashMap.GetString("Horde", sHorde, sizeof(sHorde));
	HashMap.GetString("Color", sColor, sizeof(sColor));
	HashMap.GetString("HatModel", sHModel, sizeof(sHModel));
	HashMap.GetString("IntroSound", sISound, sizeof(sISound));
	HashMap.GetString("HatPosFix", sHatPosFix, sizeof(sHatPosFix));
	HashMap.GetString("HatSize", sHatSize, sizeof(sHatSize));
	
	if(iBaseHP == -1) {
		HashMap.GetString("Base", sBase, sizeof(sBase));
		iBaseHP = StringToInt(sBase);
	}
	if(iScaleHP == -1) {
		HashMap.GetString("Scale", sScale, sizeof(sScale));
		iScaleHP = StringToInt(sScale);
	}
	if(iSize == -1.0) {
		HashMap.GetString("Size", sSize, sizeof(sSize));
		iSize = StringToFloat(sSize);
	}
	if(iGlow == -1) {
		HashMap.GetString("Glow", sGlow, sizeof(sGlow));
		iGlow = StrEqual(sGlow, "Yes") ? 1 : 0;
	}
	if(strlen(sPosition) != 0 && !isCMD) {
		char sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		for(int i = 0; i < 3; i++)
			temp[i] = StringToFloat(sPos[i]);
	}
	temp[2] += StringToFloat(sPosFix);
	gIsMultiSpawn = StringToInt(sHorde) <= 1 ? 1 : StringToInt(sHorde);
	int playerCounter = GetClientCount(true);
	int sHealth = (iBaseHP + iScaleHP*playerCounter)*(gIsMultiSpawn != 1 ? 1 : 10);
	for(int i = 0; i < gIsMultiSpawn; i++) {
		//char stringIndex[16];
		//Format(stringIndex, sizeof(stringIndex), "%d", index);
		int ent = CreateEntityByName(sType);
		DataPack pack = new DataPack();
		pack.WriteCell(EntIndexToEntRef(ent));
		pack.WriteCell(index);
		pack.WriteCell(view_as<int>(gActiveTimer));
		pack.WriteCell(gIsMultiSpawn);
		dataArray.Push(pack);
		TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(ent);
		SetEntProp(ent, Prop_Data, "m_iHealth", sHealth);
		SetEntProp(ent, Prop_Data, "m_iMaxHealth", sHealth); 
		SetEntProp(ent, Prop_Data, "m_iTeamNum", 0);
		//SetEntPropString(ent, Prop_Data, "m_iName", stringIndex);
		SetEntProp(ent, Prop_Data, "m_iTeamNum", StrEqual(sType, MONOCULUS) ? 5 : 0);
		if(strlen(sColor) != 0) {
			if(StrEqual(sColor, "Red", false)) SetEntProp(ent, Prop_Send, "m_nSkin", 0);
			else if(StrEqual(sColor, "Blue", false)) SetEntProp(ent, Prop_Send, "m_nSkin", 1);
			else if(StrEqual(sColor, "Green", false)) SetEntProp(ent, Prop_Send, "m_nSkin", 2);
			else if(StrEqual(sColor, "Yellow", false)) SetEntProp(ent, Prop_Send, "m_nSkin", 3);
			else if(StrEqual(sColor, "Random", false)) SetEntProp(ent, Prop_Send, "m_nSkin", GetRandomInt(0, 3));
		}
		if(strlen(sModel) != 0) {
			SetEntityModel(ent, sModel);
		}
		gActiveTimer ? gHCount++ : gCCount++;
		/*if(gActiveTimer == true) {
			//gHArray.Push(EntIndexToEntRef(ent));
			gHCount++;
		}
		else {
			//gCArray.Push(EntIndexToEntRef(ent));
			gCCount++;
		}*/
		if(i == 0) {
			DataPack hPack = new DataPack();
			CreateDataTimer(StringToFloat(sLifetime), RemoveTimerPrint, hPack);
			hPack.WriteCell(index);
			hPack.WriteCell(EntIndexToEntRef(ent));
		}
		CreateTimer(StringToFloat(sLifetime), RemoveTimer, EntIndexToEntRef(ent));
		if(strlen(sHModel) != 0) {
			int hat = CreateEntityByName("prop_dynamic_override");
			DispatchKeyValue(hat, "model", sHModel);
			DispatchKeyValue(hat, "spawnflags", "256");
			DispatchKeyValue(hat, "solid", "0");
			SetEntPropEnt(hat, Prop_Send, "m_hOwnerEntity", ent);
			//Hacky tacky way..
			//SetEntPropFloat(hat, Prop_Send, "m_flModelScale", iSize > 5 ? (iSize > 10 ? (iSize/5+0.80) : (iSize/4+0.75)) : (iSize/3+0.66));
			SetEntPropFloat(hat, Prop_Send, "m_flModelScale", StringToFloat(sHatSize));
			DispatchSpawn(hat);	
			
			SetVariantString("!activator");
			AcceptEntityInput(hat, "SetParent", ent, ent, 0);
			
			//maintain the offset of hat to the center of head
			if(!StrEqual(sType, MONOCULUS)) {
				SetVariantString("head");
				AcceptEntityInput(hat, "SetParentAttachment", ent, ent, 0);
				//SetVariantString("head");
				AcceptEntityInput(hat, "SetParentAttachmentMaintainOffset", ent, ent, 0);
			}
			float hatpos[3];
			hatpos[2] += StringToFloat(sHatPosFix); //-9.5*iSize
			TeleportEntity(hat, hatpos, NULL_VECTOR, NULL_VECTOR);
		}
		SetSize(iSize, ent);
		SetGlow(iGlow, ent);
	}
	if(!StrEqual(sISound, "none", false)) {
		EmitSoundToAll(sISound, _, _, _, _, 1.0);
	}
	ReplaceString(sName, sizeof(sName), "_", " ");
	CPrintToChatAll("%t", "Boss_Spawn", sName);
	if(argIndex == 1) {
		gIndex = saveIndex;
	}
	if(gActiveTimer == true) {
		gIndex++;
		if(gIndex > gArray.Length-1) gIndex = 0;
	}
}

public Action RemoveTimer(Handle hTimer, any ref) {
	int ent = EntRefToEntIndex(ref);
	if(IsValidEntity(ent)) {
		AcceptEntityInput(ent, "Kill");
	}
	
	/*for(int i = 0; i < gHArray.Length; i++) {
		int ent = EntRefToEntIndex(gHArray.Get(i));
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	for(int i = 0; i < gCArray.Length; i++) {
		int ent = EntRefToEntIndex(gCArray.Get(i));
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}*/
	/*
	if(jHUD != null) {
		for(int j = 1; j <= MaxClients; j++) {
			if(IsClientInGame(j))
				ClearSyncHud(j, jHUD);
		}
		jHUD = null;
		CloseHandle(jHUD);
	}*/
}

public Action RemoveTimerPrint(Handle hTimer, DataPack hPack) {
	hPack.Reset();
	int index = hPack.ReadCell();
	int ent = EntRefToEntIndex(hPack.ReadCell());
	if(IsValidEntity(ent)) {
		char sName[64];
		StringMap HashMap = gArray.Get(index);
		HashMap.GetString("Name", sName, sizeof(sName));
		CPrintToChatAll("%t", "Boss_Left", sName);
	}
}

//Instead of hooking to sdkhook_takedamage, we use a 0.5 timer because of hud overloading when taking damage
public Action HealthTimer(Handle hTimer, any ref) {
	if(IsValidEntity(gTrack)) {
		int HP = GetEntProp(gTrack, Prop_Data, "m_iHealth");
		int maxHP = GetEntProp(gTrack, Prop_Data, "m_iMaxHealth");
		int currentHP = RoundFloat(HP - maxHP * 0.9);
		if(currentHP > maxHP*0.1*0.65) SetHudTextParams(0.46, 0.12, 0.5, 0, 255, 0, 255);
		else if(maxHP*0.1*0.25 < currentHP < maxHP*0.1*0.65) SetHudTextParams(0.46, 0.12, 0.5, 255, 255, 0, 255);
		else SetHudTextParams(0.46, 0.12, 0.5, 255, 0, 0, 255);
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i)) {
				ShowHudText(i, -1, "HP: %d", currentHP);
			}
		}
		CreateTimer(0.5, HealthTimer, _);
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

void RemoveExistingBoss() {
	/*for(int i = 0; i < gHArray.Length; i++) {
		int ent = EntRefToEntIndex(gHArray.Get(i));
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	for(int i = 0; i < gCArray.Length; i++) {
		int ent = EntRefToEntIndex(gCArray.Get(i));
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}*/
	for(int i = 0; i < dataArray.Length; i++)
	{
		DataPack pack = dataArray.Get(i);
		int ent = EntRefToEntIndex(pack.ReadCell());
		if(!IsValidEntity(ent)) continue;
		AcceptEntityInput(ent, "Kill");
		
	}	
}

/*
void RemoveExistingBoss() {
	int ent = -1;
	while((ent = FindEntityByClassname(ent, "headless_hatman")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "eyeball_boss")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "merasmus")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "tf_zombie")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
}*/

void SetGlow(int value, int ent) {
	if(IsValidEntity(ent)) {
		SetEntProp(ent, Prop_Send, "m_bGlowEnabled", value);
	}
}

void SetSize(float value, int ent) {
	if(IsValidEntity(ent)) {
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", value);
		ResizeHitbox(ent, value);
	}
}

void ResizeHitbox(int entity, float fScale = 1.0) {
	float vecBossMin[3], vecBossMax[3];
	GetEntPropVector(entity, Prop_Send, "m_vecMins", vecBossMin);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecBossMax);
	
	float vecScaledBossMin[3], vecScaledBossMax[3];
	
	vecScaledBossMin = vecBossMin;
	vecScaledBossMax = vecBossMax;
	
	ScaleVector(vecScaledBossMin, fScale);
	ScaleVector(vecScaledBossMax, fScale);
	SetEntPropVector(entity, Prop_Send, "m_vecMins", vecScaledBossMin);
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecScaledBossMax);
}
/* --------------------------------BOSS SPAWNING CORE---------------------------------*/

/* ---------------------------------TIMER & HUD CORE----------------------------------*/
public void HUDTimer() {
	if(!gEnabled) return;
	sInterval = GetConVarFloat(cVars[2]);
	cTimer = CreateTimer(1.0, HUDCountDown, _, TIMER_REPEAT);
}

public Action HUDCountDown(Handle hTimer) {
	sInterval--;
	/*for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i))
			ClearSyncHud(i, hHUD);
	}*/
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			SetHudTextParams(sHUDx, sHUDy, 1.0, 255, 255, 255, 255);
			//ShowSyncHudText(i, hHUD, "Boss: %d seconds", RoundFloat(sInterval));
			ShowHudText(i, -1, "Boss: %d seconds", RoundFloat(sInterval));
		}
	}
	if(sInterval <= 0) {
		SpawnBoss(-1,-1.0,-1);
		/*for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i))
				ClearSyncHud(i, hHUD);
		}*/
		cTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

void ResetTimer() {
	CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
	ClearTimer(cTimer);
	HUDTimer();
}
/* ---------------------------------TIMER & HUD CORE----------------------------------*/

/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/
public void OnEntityCreated(int ent, const char[] classname) {
	if(!gEnabled) return;
	if(StrEqual(classname, "monster_resource")) {
		gHPbar = ent;
		//jHUD = CreateHudSynchronizer();
	}
	else if((StrEqual(classname, HORSEMAN) || StrEqual(classname, MONOCULUS) || StrEqual(classname, MERASMUS) || StrEqual(classname, SKELETON))) {
		/* Too lazy to work on this
		if(StrEqual(classname, SKELETON)) {
			for(int i = 1; i <= MaxClients; i++) {
				if(!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
				float btemp[3], itemp[3];
				GetEntPropVector(ent, Prop_Send, "m_vecOrigin", btemp);
				GetClientAbsOrigin(i, itemp);
				float Distance = GetVectorDistance(btemp, itemp);
				if(Distance <= 5000) {
					int flags = GetCommandFlags("shake"); 
					SetCommandFlags("shake", flags & ~FCVAR_CHEAT);
					FakeClientCommand(i, "shake");	
					SetCommandFlags("shake", flags | FCVAR_CHEAT);
				}
			}			
		}*/
		if(gTrack == -1 && gIsMultiSpawn == 1) {
			gTrack = ent;
			RequestFrame(UpdateBossHealth, ent);
			//SDKHook(ent, SDKHook_SpawnPost, UpdateBossHealth);
			SDKHook(ent, SDKHook_OnTakeDamagePost, OnBossDamaged);
			gIsMultiSpawn = 0;
			CreateTimer(0.5, HealthTimer, _);
		}
	}
	else if(StrEqual(classname, "prop_dynamic")) {
		RequestFrame(OnPropSpawn, EntIndexToEntRef(ent));
	}
}

public void OnEntityDestroyed(int ent) {
	if(!gEnabled) return;
	if(!IsValidEntity(ent)) return;
	if(ent == gTrack) {
		//need to fix this later but too lazy atm
		gTrack = FindEntityByClassname(-1, HORSEMAN);
		if(gTrack == ent) {
			gTrack = FindEntityByClassname(ent, HORSEMAN);
		}
		if(gTrack == -1) {
			gTrack = FindEntityByClassname(-1, MONOCULUS);
			if(gTrack == ent) {
				gTrack = FindEntityByClassname(ent, HORSEMAN);
			}
		}
		if(gTrack == -1) {
			gTrack = FindEntityByClassname(-1, MERASMUS);
			if (gTrack == ent) {
				gTrack = FindEntityByClassname(ent, MERASMUS);
			}
		}
		if(gTrack == -1) {
			gTrack = FindEntityByClassname(-1, SKELETON);
			if (gTrack == ent) {
				gTrack = FindEntityByClassname(ent, SKELETON);
			}
		}
		if (gTrack != -1) {
			SDKHook(gTrack, SDKHook_OnTakeDamagePost, OnBossDamaged);
		}
		RequestFrame(UpdateBossHealth, gTrack);
	}
	for(int i = 0; i < dataArray.Length; i++)
	{
		DataPack pack = dataArray.Get(i);
		pack.Reset();
		int boss = EntRefToEntIndex(pack.ReadCell());
		if(boss == ent)
		{
			int index = pack.ReadCell();
			bool timer = view_as<bool>(pack.ReadCell());
			int max = pack.ReadCell()-1;
			StringMap HashMap = gArray.Get(index);
			if(max == 0)
			{
				char sDSound[256];
				HashMap.GetString("DeathSound", sDSound, sizeof(sDSound));
				if(!StrEqual(sDSound, "none", false)) 
				{
					EmitSoundToAll(sDSound, _, _, _, _, 1.0);
				}
				if(GetClientCount(true) >= sMin) 
				{
					HUDTimer();
					CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
				}
				if(timer && GetClientCount(true) >= sMin) {
					HUDTimer();
					CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
				}
				delete pack;
			}
			else
			{
				int pack_position = pack.Position;
				SetPackPosition(pack, pack_position-1);
				pack.WriteCell(max);
			}
		}
		
	}
}

public void OnPropSpawn(any ref) {
	int ent = EntRefToEntIndex(ref);
	if(!IsValidEntity(ent)) return;
	int parent = GetEntPropEnt(ent, Prop_Data, "m_pParent");
	if(!IsValidEntity(parent)) return;
	char strClassname[64];
	GetEntityClassname(parent, strClassname, sizeof(strClassname));
	if(StrEqual(strClassname, HORSEMAN, false)) {
		int bIndex = -1;
		for(int i = 0; i < dataArray.Length; i++) {
			DataPack pack = dataArray.Get(i);
			pack.Reset();
			int boss = EntRefToEntIndex(pack.ReadCell());
			if(boss == parent) {
				bIndex = pack.ReadCell();
				break;
			}
		}
		char sWModel[256];
		StringMap HashMap = gArray.Get(bIndex);
		HashMap.GetString("WeaponModel", sWModel, sizeof(sWModel));
		
		if(strlen(sWModel) != 0) {
			if(StrEqual(sWModel, "Invisible")) {
				SetEntityModel(ent, "");
			}
			else {
				SetEntityModel(ent, sWModel);
				SetEntPropEnt(parent, Prop_Send, "m_hActiveWeapon", ent);
			}
		}
	}
}
/*
public void OnBossSpawned(any ref) {
	int ent = EntRefToEntIndex(ref);
	if(!IsValidEntity(ent)) return;
	RequestFrame(UpdateBossHealth, ref);
}*/

void FindHealthBar() {
	gHPbar = FindEntityByClassname(-1, "monster_resource");
	if(gHPbar == -1) {
		gHPbar = CreateEntityByName("monster_resource");
		if(gHPbar != -1) {
			DispatchSpawn(gHPbar);
		}
	}
}

public Action OnBossDamaged(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	//char classname[32];
	//GetEntityClassname(attacker, classname, sizeof(classname));
	//PrintToChatAll("victim: %d | attacker: %d | damage: %f | type: %d | name: %s", victim, attacker, damage, damagetype, classname);
	/*if(damagetype & DMG_CRUSH || damagetype & DMG_VEHICLE) {
		damage = 0.0;
		return Plugin_Changed;
	}*/
	UpdateBossHealth(victim);
}

public Action OnClientDamaged(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if(!IsClientInGame(victim)) return Plugin_Continue;
	if(!IsValidEntity(attacker)) return Plugin_Continue;
	char classname[32];
	GetEntityClassname(attacker, classname, sizeof(classname));
	if(StrEqual(classname, HORSEMAN) || StrEqual(classname, MONOCULUS) || StrEqual(classname, MERASMUS) || StrEqual(classname, SKELETON)) {
		char sDamage[32];
		int bIndex = -1;
		for(int i = 0; i < dataArray.Length; i++) {
			DataPack pack = dataArray.Get(i);
			pack.Reset();
			int boss = EntRefToEntIndex(pack.ReadCell());
			if(boss == attacker) {
				bIndex = pack.ReadCell();
				break;
			}
		}
		for(int i = 0; i < gArray.Length; i++) {
			if(i == bIndex) {
				StringMap HashMap = gArray.Get(i);
				HashMap.GetString("Damage", sDamage, sizeof(sDamage));
				break;
			}
		}
		damage = StringToFloat(sDamage);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void UpdateBossHealth(int ent) {
	//int ent = EntRefToEntIndex(ref);
	if (gHPbar == -1) return;
	int percentage;
	if(IsValidEntity(ent)) {
		int HP = GetEntProp(ent, Prop_Data, "m_iHealth");
		int maxHP = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
		int currentHP = RoundFloat(HP - maxHP * 0.9);
		if(currentHP <= 0) {
			percentage = 0;
			SetEntProp(ent, Prop_Data, "m_iHealth", 0);
			
			if(HP <= -1) {
				SetEntProp(ent, Prop_Data, "m_takedamage", 0);
			}
			char classname[32];
			GetEntityClassname(ent, classname, sizeof(classname));
			int bIndex = -1;
			for(int i = 0; i < dataArray.Length; i++) {
				DataPack pack = dataArray.Get(i);
				pack.Reset();
				int boss = EntRefToEntIndex(pack.ReadCell());
				if(boss == ent) {
					bIndex = pack.ReadCell();
					break;
				}
			}
			char sGnome[8];
			StringMap HashMap = gArray.Get(bIndex);
			HashMap.GetString("Gnome", sGnome, sizeof(sGnome));
			//This makes it so that skeleton kill die without spawning the gnome ones
			if(StringToInt(sGnome) == 0 && StrEqual(classname, SKELETON)) {
				AcceptEntityInput(ent, "kill");
			}
		}
		else {
			percentage = RoundToCeil((float(HP) / float(maxHP / 10)) * 255.9);	//max 255.9 accurate at 100%
		}
	}
	else {
		percentage = 0;
	}
	SetEntProp(gHPbar, Prop_Send, "m_iBossHealthPercentageByte", percentage);
}

public void ClearTimer(Handle &timer) {  
	if(timer != null) {  
		KillTimer(timer);  
	}  
	timer = null;  
}  
/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/

/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/
public void SetupMapConfigs(const char[] sFile) {
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss] Error: Can not find map filepath %s", sPath);
	}
	KeyValues kv = CreateKeyValues("Boss Spawner Map");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) {
		LogError("[Boss] Could not read maps file: %s", sPath);
		SetFailState("[Boss] Could not read maps file: %s", sPath);
	}
	
	int mapEnabled = 0;
	bool Default = false;
	int tempEnabled = 0;
	float temp_pos[3];
	char requestMap[64], currentMap[64], sPosition[64], tPosition[64];
	GetCurrentMap(currentMap, sizeof(currentMap));
	do {
		kv.GetSectionName(requestMap, sizeof(requestMap));
		if(StrEqual(requestMap, currentMap, false)) {
			mapEnabled = kv.GetNum("Enabled", 0);
			gPos[0] = kv.GetFloat("Position X", 0.0);
			gPos[1] = kv.GetFloat("Position Y", 0.0);
			gPos[2] = kv.GetFloat("Position Z", 0.0);
			kv.GetString("TeleportPosition", sPosition, sizeof(sPosition), SNULL);
			Default = true;
		}
		else if(StrEqual(requestMap, "Default", false)) {
			tempEnabled = kv.GetNum("Enabled", 0);
			temp_pos[0] = kv.GetFloat("Position X", 0.0);
			temp_pos[1] = kv.GetFloat("Position Y", 0.0);
			temp_pos[2] = kv.GetFloat("Position Z", 0.0);
			kv.GetString("TeleportPosition", tPosition, sizeof(tPosition), SNULL);
		}
	} while kv.GotoNextKey();
	delete kv;
	if(Default == false) {
		mapEnabled = tempEnabled;
		gPos = temp_pos;
		Format(sPosition, sizeof(sPosition), "%s", tPosition);
	}
	float tpos[3];
	if(strlen(sPosition) != 0) {
		int ent;
		while((ent = FindEntityByClassname(ent, "info_target")) != -1) {
			if(IsValidEntity(ent)) {
				char strName[32];
				GetEntPropString(ent, Prop_Data, "m_iName", strName, sizeof(strName));
				if(StrContains(strName, "spawn_loot")) {
					AcceptEntityInput(ent, "Kill");
				}
			}
		}
		char sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		tpos[0] = StringToFloat(sPos[0]);
		tpos[1] = StringToFloat(sPos[1]);
		tpos[2] = StringToFloat(sPos[2]);
		
		for(int i = 0; i < 4; i++) {
			ent = CreateEntityByName("info_target");
			char spawn_name[16];
			Format(spawn_name, sizeof(spawn_name), "%s", i == 0 ? "spawn_loot" : (i == 1 ? "spawn_loot_red" : (i == 2 ? "spawn_loot_blue" : "spawn_loot_alt")));
			SetEntPropString(ent, Prop_Data, "m_iName", spawn_name);
			TeleportEntity(ent, tpos, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
		}
	}
	if(mapEnabled != 0) {
		gEnabled = true;
		if(GetClientCount(true) >= sMin) {
			HUDTimer();
			CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
		}
	}
	else if(mapEnabled == 0) {
		gEnabled = false;
	}
	LogMessage("Loaded Map configs successfully."); 
}

public void SetupBossConfigs(const char[] sFile) {
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss] Error: Can not find map filepath %s", sPath);
	}
	Handle kv = CreateKeyValues("Custom Boss Spawner");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) {
		LogError("[Boss] Could not read maps file: %s", sPath);
		SetFailState("[Boss] Could not read maps file: %s", sPath);
	}
	gArray.Clear();
	char sName[64], sModel[256], sType[32], sBase[16], sScale[16], sWModel[256], sSize[16], sGlow[8], sPosFix[32];
	char sLifetime[32], sPosition[32], sHorde[8], sColor[16], sISound[256], sDSound[256], sHModel[256], sGnome[8];
	char sHatPosFix[32], sHatSize[16], sDamage[32];
	static int init = 0;
	do {
		KvGetSectionName(kv, sName, sizeof(sName));
		KvGetString(kv, "Model", sModel, sizeof(sModel), SNULL);
		KvGetString(kv, "Type", sType, sizeof(sType));
		KvGetString(kv, "HP Base", sBase, sizeof(sBase), "10000");
		KvGetString(kv, "HP Scale", sScale, sizeof(sScale), "1000");
		KvGetString(kv, "WeaponModel", sWModel, sizeof(sWModel), SNULL);
		KvGetString(kv, "Size", sSize, sizeof(sSize), "1.0");
		KvGetString(kv, "Glow", sGlow, sizeof(sPosFix), "Yes");
		KvGetString(kv, "PosFix", sPosFix, sizeof(sPosFix), "0.0");
		KvGetString(kv, "Lifetime", sLifetime, sizeof(sLifetime), "120");
		KvGetString(kv, "Position", sPosition, sizeof(sPosition), SNULL);
		KvGetString(kv, "Horde", sHorde, sizeof(sHorde), "1");
		KvGetString(kv, "Color", sColor, sizeof(sColor), SNULL);
		KvGetString(kv, "IntroSound", sISound, sizeof(sISound), INTRO_SND);
		KvGetString(kv, "DeathSound", sDSound, sizeof(sDSound), DEATH_SND);
		KvGetString(kv, "HatModel", sHModel, sizeof(sHModel), SNULL);
		KvGetString(kv, "Gnome", sGnome, sizeof(sGnome), "0");
		KvGetString(kv, "HatPosFix", sHatPosFix, sizeof(sHatPosFix), "0.0");
		KvGetString(kv, "HatSize", sHatSize, sizeof(sHatSize), "1.0");
		KvGetString(kv, "Damage", sDamage, sizeof(sDamage), "100.0");
		
		if(StrContains(sName, " ") != -1) {
			LogError("[Boss] Boss name should not have spaces, please replace spaces with _");
			SetFailState("[Boss] Boss name should not have spaces, please replace spaces with _");
		}
		if(!StrEqual(sType, HORSEMAN) && !StrEqual(sType, MONOCULUS) && !StrEqual(sType, MERASMUS) && !StrEqual(sType, SKELETON)){
			LogError("[Boss] Type is undetermined, please check boss type again.");
			SetFailState("[Boss] Type is undetermined, please check boss type again.");
		}
		if(!StrEqual(sType, SKELETON)) {
			if(!StrEqual(sHorde, "1")) {
				LogError("[Boss] Horde mode only works for Type: tf_zombie.");
				SetFailState("[Boss] Horde mode only works for Type: tf_zombie.");
			}
			if(strlen(sColor) != 0) {
				LogError("[Boss] Color mode only works for Type: tf_zombie.");
				SetFailState("[Boss] Color mode only works for Type: tf_zombie.");
			}
			if(!StrEqual(sGnome, "0")) {
				LogError("[Boss] Gnome only works for Type: tf_zombie.");
				SetFailState("[Boss] Gnome only works for Type: tf_zombie.");
			}
		}
		if(StrEqual(sType, MONOCULUS)) {
			RemoveBossLifeline("tf_eyeball_boss_lifetime", "tf_eyeball_boss_lifetime", StringToInt(sLifetime)+1);
		}
		else if(StrEqual(sType, MERASMUS)) {
			RemoveBossLifeline("tf_merasmus_lifetime", "tf_merasmus_lifetime", StringToInt(sLifetime)+1);
		}
		if(!StrEqual(sType, HORSEMAN)) {
			if(strlen(sWModel) != 0) {
				LogError("[Boss] Weapon model can only be changed on Type:headless_hatman");
				SetFailState("[Boss] Weapon model can only be changed on Type:headless_hatman");
			}
		}
		else if(strlen(sWModel) != 0) {
			if(!StrEqual(sWModel, "Invisible")) {
				PrecacheModel(sWModel, true);
			}
		}
		if(strlen(sModel) != 0) {
			PrecacheModel(sModel, true);
		}
		if(strlen(sHModel) != 0) {
			PrecacheModel(sHModel, true);
		}
		PrecacheSound(sISound);
		PrecacheSound(sDSound);
		StringMap HashMap = new StringMap();
		HashMap.SetString("Name", sName, false);
		HashMap.SetString("Model", sModel, false);
		HashMap.SetString("Type", sType, false);
		HashMap.SetString("Base", sBase, false);
		HashMap.SetString("Scale", sScale, false);
		HashMap.SetString("WeaponModel", sWModel, false);
		HashMap.SetString("Size", sSize, false);
		HashMap.SetString("Glow", sGlow, false);
		HashMap.SetString("PosFix", sPosFix, false);
		HashMap.SetString("Lifetime", sLifetime, false);
		HashMap.SetString("Position", sPosition, false);
		HashMap.SetString("Horde", sHorde, false);
		HashMap.SetString("Color", sColor, false);
		HashMap.SetString("IntroSound", sISound, false);
		HashMap.SetString("DeathSound", sDSound, false);
		HashMap.SetString("HatModel", sHModel, false);
		HashMap.SetString("Gnome", sGnome, false);
		HashMap.SetString("HatPosFix", sHatPosFix, false);
		HashMap.SetString("HatSize", sHatSize, false);
		HashMap.SetString("Damage", sDamage, false);
		gArray.Push(HashMap);
		char command[64];
		Format(command, sizeof(command), "sm_%s", sName);
		if(init == 1) {
			RemoveCommandListener(SpawnBossCommand, command);
		}
		AddCommandListener(SpawnBossCommand, command);
	} while (KvGotoNextKey(kv));
	init = 1;
	CloseHandle(kv);
	LogMessage("[Boss] Custom Boss Spawner Configuration has loaded successfully."); 
}

public void SetupDownloads(const char[] sFile) {
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss] Error: Can not find download file %s", sPath);
		SetFailState("[Boss] Error: Can not find download file %s", sPath);
	}
	File file = OpenFile(sPath, "r");
	char buffer[256], fName[128], fPath[256];
	while(!file.EndOfFile() && file.ReadLine(buffer, sizeof(buffer))) {
		int i = -1;
		i = FindCharInString(buffer, '\n', true);
		if(i != -1) buffer[i] = '\0';
		TrimString(buffer);
		//Format(buffer, sizeof(buffer), "%s\\", buffer);
		//PrintToServer("%s", buffer);
		if(!DirExists(buffer)) {
			LogError("[Boss] Error: '%s' directory can not be found.", buffer);
			SetFailState("[Boss] Error: '%s' directory can not be found.", buffer);
		}
		int isMaterial = 0;
		if(StrContains(buffer, "materials/", true) != -1 || StrContains(buffer, "materials\\", true) != -1) {
			isMaterial = 1;
		}
		DirectoryListing sDir = OpenDirectory(buffer, true);
		while(sDir.GetNext(fName, sizeof(fName))) {
			if(StrEqual(fName, ".") || StrEqual(fName, "..")) 
				continue;
			if(StrContains(fName, ".ztmp") != -1) 
				continue;
			if(StrContains(fName, ".bz2") != -1)
				continue;
			Format(fPath, sizeof(fPath), "%s/%s", buffer, fName);
			AddFileToDownloadsTable(fPath);
			if(isMaterial == 1) 
				continue;
			if(StrContains(fName, ".vtx") != -1)
				continue;
			if(StrContains(fName, ".vvd") != -1)
				continue;
			if(StrContains(fName, ".phy") != -1)
				continue;
			PrecacheGeneric(fPath, true);
		}
		delete sDir;
	}
	delete file;
}
/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/

/* ----------------------------------------END----------------------------------------*/