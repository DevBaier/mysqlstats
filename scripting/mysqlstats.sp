#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#pragma newdecls required
#pragma semicolon 1

Database mS_MySQL = null;

int mS_PlayerKills[MAXPLAYERS + 1] = 0;
int mS_PlayerKnifeKills[MAXPLAYERS + 1] = 0;
int mS_PlayerDeaths[MAXPLAYERS + 1] = 0;
int mS_PlayerHS[MAXPLAYERS + 1] = 0;
int mS_PlayerAssists[MAXPLAYERS + 1] = 0;


public Plugin myinfo =
{
	name = "CSGO MySQL Stats",
	author = "Daniel Baier",
	description = "Get CSGO Stats in a MySQL Database",
	version = "1.0",
	url = "https://github.com/devbaier/mysqlstats"
};


public void OnPluginStart() {
	
	RegConsoleCmd("sm_stats", Cmd_Stats, "Description");
	
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("round_end", Event_RoundEnd);
	
	SQL_StartConnection();
	
}

public void OnClientPutInServer(int client) {
	
	if (!IsValidClient(client))
	{
		return;
	}
	
	if (mS_MySQL == null)
	{
		return;
	}
	
	mS_PlayerKills[client] = 0;
	mS_PlayerKnifeKills[client] = 0;
	mS_PlayerDeaths[client] = 0;
	mS_PlayerHS[client] = 0;
	mS_PlayerAssists[client] = 0;
	
	char mS_PlayerName[MAX_NAME_LENGTH];
	GetClientName(client, mS_PlayerName, MAX_NAME_LENGTH);
	
	char mS_SteamID64[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, mS_SteamID64, 32))
	{
		return;
	}
	
	
	int iLength = ((strlen(mS_PlayerName) * 2) + 1);
	char[] mS_EscapedName = new char[iLength];
	mS_MySQL.Escape(mS_PlayerName, mS_EscapedName, iLength);
	
	char mS_ClientIP[64];
	GetClientIP(client, mS_ClientIP, 64);
	
	char mS_Query[512];
	FormatEx(mS_Query, 512, "INSERT INTO `players` (`steamid`, `name`, `ip`) VALUES ('%s', '%s', '%s') ON DUPLICATE KEY UPDATE `name` = '%s', `ip` = '%s'", mS_SteamID64, mS_EscapedName, mS_ClientIP, mS_EscapedName, mS_ClientIP);
	LogMessage("INSERT INTO `players` (`steamid`, `name`, `ip`) VALUES ('%s', '%s', '%s') ON DUPLICATE KEY UPDATE `name` = '%s', `ip` = '%s'", mS_SteamID64, mS_EscapedName, mS_ClientIP, mS_EscapedName, mS_ClientIP);
	mS_MySQL.Query(MySQL_InsertPlayer_Callback, mS_Query, GetClientSerial(client), DBPrio_Normal);
}

public void OnClientDisconnect(int client) {
	
	if (!IsValidClient(client))
	{
		return;
	}
	
	if (mS_MySQL == null)
	{
		return;
	}
	
	UpdatePlayersStats(client);
}

public Action Cmd_Stats(int client, int args) {
	
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}
	
	char mS_SteamID64[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, mS_SteamID64, 32))
	{
		return Plugin_Handled;
	}
	
	OpenStatsMenu(client, client);
	
	return Plugin_Handled;
}

public int Stats_MenuHandler(Menu menu, MenuAction action, int client, int item) {
	
	if (action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void OpenStatsMenu(int client, int displayto) {
	
	Menu menu = new Menu(Stats_MenuHandler);
	
	char mS_PlayerName[MAX_NAME_LENGTH];
	GetClientName(client, mS_PlayerName, MAX_NAME_LENGTH);
	char mS_Title[32];
	FormatEx(mS_Title, 32, "%s's stats :", mS_PlayerName);
	menu.SetTitle(mS_Title);
	
	char mH_Kills[128], mH_KnifeKills[128], mH_Deaths[128], mH_HeadShots[128], mH_Assists[128];
	
	FormatEx(mH_Kills, 128, "Your total kills : %d", mS_PlayerKills[client]);
	FormatEx(mH_KnifeKills, 128, "Your total knife kills : %d", mS_PlayerKills[client]);
	FormatEx(mH_Deaths, 128, "Your total deaths : %d", mS_PlayerDeaths[client]);
	FormatEx(mH_HeadShots, 128, "Your total headshots : %d", mS_PlayerHS[client], mS_PlayerHS);
	FormatEx(mH_Assists, 128, "Your total assists : %d", mS_PlayerAssists[client]);
	
	menu.AddItem("", mH_Kills, ITEMDRAW_DISABLED);
	menu.AddItem("", mH_KnifeKills, ITEMDRAW_DISABLED);
	menu.AddItem("", mH_Deaths, ITEMDRAW_DISABLED);
	menu.AddItem("", mH_HeadShots, ITEMDRAW_DISABLED);
	menu.AddItem("", mH_Assists, ITEMDRAW_DISABLED);
	
	menu.ExitButton = true;
	menu.Display(displayto, 30);
	
}

void SQL_StartConnection() {
	
	
	if (mS_MySQL != null)
	{
		delete mS_MySQL;
	}
	
	char mS_Error[255];
	if (SQL_CheckConfig("mysqlstats"))
	{
		mS_MySQL = SQL_Connect("mysqlstats", true, mS_Error, 255);
		
		if (mS_MySQL == null)
		{
			SetFailState("[MS] Error on start. Reason: %s", mS_Error);
		}
	}
	else
	{
		SetFailState("[MS] Cant find `mysqlstats` on database.cfg");
	}
	
	mS_MySQL.SetCharset("utf8");
	
	char mS_Query[512];	
	FormatEx(mS_Query, 512, "CREATE TABLE IF NOT EXISTS `players` (`steamid` VARCHAR(17) NOT NULL, `ip` VARCHAR(64), `name` VARCHAR(32), `kills` INT(11) NOT NULL DEFAULT 0, `deaths` INT(11) NOT NULL DEFAULT 0, `knifekills` INT(11) NOT NULL DEFAULT 0, `headshots` INT(11) NOT NULL DEFAULT 0, `assists` INT(11) NOT NULL DEFAULT 0, PRIMARY KEY (`steamid`))");
	if (!SQL_FastQuery(mS_MySQL, mS_Query))
	{
		SQL_GetError(mS_MySQL, mS_Error, 255);
		LogError("[MS] Cant create table. Error : %s", mS_Error);
	}
	
}

void UpdatePlayersStats(int client) {

	if (mS_MySQL == null)
	{
		return;
	}
	
	char mS_SteamID64[32];
	
	if (!GetClientAuthId(client, AuthId_SteamID64, mS_SteamID64, 32))
	{
		return;
	}
	
	char mS_Query[512];
	FormatEx(mS_Query, 512, "UPDATE `players` SET `kills`= %d, `deaths`= %d, `knifekills`= %d, `headshots`= %d, `assists`= %d WHERE `steamid` = '%s'", mS_PlayerKills[client], mS_PlayerDeaths[client], mS_PlayerKnifeKills[client], mS_PlayerHS[client], mS_PlayerAssists[client], mS_SteamID64);
	mS_MySQL.Query(MySQL_UpdatePlayer_Callback, mS_Query, GetClientSerial(client), DBPrio_Normal);
}

public void Event_PlayerDeath(Event e, const char[] name, bool dontBroadcast) {
	
	if (InWarmUP())
	{
		return;
	}
	
	int client = GetClientOfUserId(GetEventInt(e, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(e, "attacker"));
	bool headshot = GetEventBool(e, "headshot");
	int assister = GetClientOfUserId(GetEventInt(e, "assister"));
	
	if (!IsValidClient(client) || !IsValidClient(attacker))
	{
		return;
	}

	if(attacker == client) {
		return;
	}
	
	mS_PlayerKills[attacker]++;
	mS_PlayerDeaths[client]++;
	
	char weapon[13];
	GetEventString(e, "weapon", weapon, sizeof(weapon));
	
	if(StrEqual(weapon, "knife"))
		mS_PlayerKnifeKills[attacker]++;
	
	if (headshot)
		mS_PlayerHS[attacker]++;
	
	if (assister)
		mS_PlayerAssists[assister]++;
}

public void Event_PlayerSpawn(Event e, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(e, "userid"));
	
	//PrintToChat(client, "Kills %d", mS_PlayerKills[client]);
	//PrintToChat(client, "Knife Kills %d", mS_PlayerKnifeKills[client]);
	//PrintToChat(client, "Deaths %d", mS_PlayerDeaths[client]);
	//PrintToChat(client, "HeadShots %d", mS_PlayerHS[client]);
	//PrintToChat(client, "Assist %d", mS_PlayerAssists[client]);
}

public void Event_RoundEnd(Event e, const char[] name, bool dontBroadcast) {	
	if (mS_MySQL == null)
	{
		return;
	}
	
	for (int i = 0; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			UpdatePlayersStats(i);
		}
	}
}

public void MySQL_InsertPlayer_Callback(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientFromSerial(data);
	if (results == null)
	{
		if (client == 0)
		{
			LogError("[SS] Client is not valid. Reason: %s", error);
		}
		else
		{
			LogError("[SS] Cant use client data. Reason: %s", client, error);
		}
		return;
	}
	
	char mS_SteamID64[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, mS_SteamID64, 32))
	{
		return;
	}
	
	
	char mS_Query[512];
	
	FormatEx(mS_Query, 512, "SELECT `kills`, `deaths`, `knifekills`, `headshots`, `assists` FROM `players` WHERE `steamid` = '%s'", mS_SteamID64);
	mS_MySQL.Query(MySQL_SelectPlayer_Callback, mS_Query, GetClientSerial(client), DBPrio_Normal);
}

public void MySQL_UpdatePlayer_Callback(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientFromSerial(data);
	if (results == null)
	{
		if (client == 0)
		{
			LogError("[SS] Client is not valid. Reason: %s", error);
		}
		else
		{
			LogError("[SS] Cant use client data. Reason: %s", client, error);
		}
		return;
	}
}

public void MySQL_SelectPlayer_Callback(Database db, DBResultSet results, const char[] error, any data) {
	if (results == null)
	{
		LogError("[SS] Selecting player error. Reason: %s", error);
		return;
	}
	
	int client = GetClientFromSerial(data);
	if (client == 0)
	{
		LogError("[SS] Client is not valid. Reason: %s", error);
		return;
	}
	
	while (results.FetchRow())
	{
		mS_PlayerKills[client] = results.FetchInt(0);
		mS_PlayerKnifeKills[client] = results.FetchInt(1);
		mS_PlayerDeaths[client] = results.FetchInt(2);
		mS_PlayerHS[client] = results.FetchInt(3);
		mS_PlayerAssists[client] = results.FetchInt(4);
	}
}

public int Native_GetKillsAmount(Handle handler, int numParams) {
	return mS_PlayerKills[GetNativeCell(1)];
}

public int Native_GetKnifeKillsAmount(Handle handler, int numParams) {
	return mS_PlayerKnifeKills[GetNativeCell(1)];
}

public int Native_GetDeathsAmount(Handle handler, int numParams) {
	return mS_PlayerDeaths[GetNativeCell(1)];
}

public int Native_GetHSAmount(Handle handler, int numParams) {
	return mS_PlayerHS[GetNativeCell(1)];
}

public int Native_GetAssistsAmount(Handle handler, int numParams) {
	return mS_PlayerAssists[GetNativeCell(1)];
}

stock bool IsValidClient(int client, bool alive = false, bool bots = false) {
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && (alive == false || IsPlayerAlive(client)) && (bots == false && !IsFakeClient(client)))
	{
		return true;
	}
	return false;
}

stock bool InWarmUP() {
	return GameRules_GetProp("m_bWarmupPeriod") != 0;
}