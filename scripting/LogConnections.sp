#define PLUGIN_NAME           "Log Connections"
#define PLUGIN_AUTHOR         "Snowy"
#define PLUGIN_DESCRIPTION    "Logs user and player connections"
#define PLUGIN_VERSION        "1.01"
#define PLUGIN_URL            ""

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <geoip>

#pragma semicolon 1
#pragma newdecls required

#define PLAYER_LOGPATH "logs/connections/player"
#define ADMIN_LOGPATH "logs/connections/admin"

enum LOGTYPE
{
    LOG_ADMIN,
    LOG_PLAYER
}

enum struct Player
{
    bool Connected;
    bool Admin;

    bool ChatMessage;
    bool ConsoleMessage;
    
    void ResetCookies()
    {
        this.ChatMessage = false;
        this.ConsoleMessage = false;
    }
}

Player g_Player[MAXPLAYERS+1];
char g_sAdminFilePath[PLATFORM_MAX_PATH];
char g_sPlayerFilePath[PLATFORM_MAX_PATH];
Cookie g_cConnectWatch;

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
};

public void OnPluginStart()
{
    BuildPath(Path_SM, g_sPlayerFilePath, sizeof(g_sPlayerFilePath), PLAYER_LOGPATH);
    if (!DirExists(g_sPlayerFilePath))
        if (!CreateDirectory(g_sPlayerFilePath, 511))
            LogMessage("Failed to create directory at %s", PLAYER_LOGPATH);
    
    BuildPath(Path_SM, g_sAdminFilePath, sizeof(g_sAdminFilePath), ADMIN_LOGPATH);
    if (!DirExists(g_sAdminFilePath))
        if (!CreateDirectory(g_sAdminFilePath, 511))
            LogMessage("Failed to create directory at %s", ADMIN_LOGPATH);
            
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
    
    g_cConnectWatch = RegClientCookie("connectwatch_cookies", "ConnectWatch client pref settings", CookieAccess_Protected);
    RegAdminCmd("sm_connectwatch", Command_ConnectWatch, ADMFLAG_GENERIC, "Toggles connectwatch");
    RegAdminCmd("sm_cw", Command_ConnectWatch, ADMFLAG_GENERIC, "Toggles connectwatch");
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            g_Player[i].Connected = true;
            if (IsClientAdmin(i))
                g_Player[i].Admin = true;
        }
        
        if (!AreClientCookiesCached(i))
            continue;
            
        OnClientCookiesCached(i);
    }
}

public void OnMapStart()
{
    char formattedTime[64], mapName[64];
    
    int currentTime = GetTime();
    GetCurrentMap(mapName, sizeof(mapName));
    
    FormatTime(formattedTime, sizeof(formattedTime), "%d_%b_%Y", currentTime);
    
    BuildPath(Path_SM, g_sPlayerFilePath, sizeof(g_sPlayerFilePath), "%s/%s_player.txt", PLAYER_LOGPATH, formattedTime);
    BuildPath(Path_SM, g_sAdminFilePath, sizeof(g_sAdminFilePath), "%s/%s_admin.txt", ADMIN_LOGPATH, formattedTime);
    
    Log(LOG_ADMIN, false, "");
    Log(LOG_ADMIN, true, "===== Map Changed To %s =====", mapName);
    Log(LOG_PLAYER, false, "");
    Log(LOG_PLAYER, true, "===== Map Changed To %s =====", mapName);
}

public void OnClientCookiesCached(int client)
{
    char value[3];
    g_cConnectWatch.Get(client, value, sizeof(value));
    if (value[0] == '\0')
    {
        g_Player[client].ChatMessage = false;
        g_Player[client].ConsoleMessage = false;
        SaveAndSetCookies(client);
    }
    else
    {
        char buffer[3];
        FormatEx(buffer, sizeof(buffer), "%c", value[0]);
        g_Player[client].ChatMessage = StrEqual(buffer, "1");
        FormatEx(buffer, sizeof(buffer), "%c", value[1]);
        g_Player[client].ConsoleMessage = StrEqual(buffer, "1");
    }
}

public void OnRebuildAdminCache(AdminCachePart part)
{
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsClientAdmin(i))
            g_Player[i].Admin = true;
}

public void OnClientPostAdminCheck(int client)
{
    if (!client || IsFakeClient(client) || g_Player[client].Connected)
        return;
        
    char playerName[128], authID[64], countryName[64], IPAddress[32];
    
    GetClientName(client, playerName, sizeof(playerName));
    GetClientIP(client, IPAddress, sizeof(IPAddress));
    
    if (!GeoipCountry(IPAddress, countryName, sizeof(countryName)))
        Format(countryName, sizeof(countryName), "Unknown Country");
    
    if (!GetClientAuthId(client, AuthId_Steam2, authID, sizeof(authID)))
        Format(authID, sizeof(authID), "Unknown SteamID");
        
    g_Player[client].Connected = true;
    
    if (IsClientAdmin(client))
    {
        g_Player[client].Admin = true;
        Log(LOG_ADMIN, true, "<%s> <%s> <%s> CONNECTED from <%s>", playerName, authID, IPAddress, countryName);
    }
    else
    {
        g_Player[client].Admin = false;
        Log(LOG_PLAYER, true, "<%s> <%s> <%s> CONNECTED from <%s>", playerName, authID, IPAddress, countryName);
    }
    
    PrintMessageToAdmins(" \x02+ \x10[%s] [%s] \x05connected from \x04[%s]", playerName, authID, countryName);
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    g_Player[client].Connected = false;
        
    if (!client || IsFakeClient(client))
        return;
        
    char playerName[128], discReason[256], authID[64], IPAddress[32];
    int connectionTime = -1;
    
    GetClientName(client, playerName, sizeof(playerName));
    GetClientIP(client, IPAddress, sizeof(IPAddress));
    event.GetString("reason", discReason, sizeof(discReason));
    
    if (!GetClientAuthId(client, AuthId_Steam2, authID, sizeof(authID)))
        Format(authID, sizeof(authID), "Unknown SteamID");
        
    if (IsClientInGame(client))
        connectionTime = RoundToCeil(GetClientTime(client) / 60);
        
    if (g_Player[client].Admin)
        Log(LOG_ADMIN, true, "<%s> <%s> <%s> DISCONNECTED after %d minutes. <%s>", playerName, authID, IPAddress, connectionTime, discReason);
    else
        Log(LOG_PLAYER, true, "<%s> <%s> <%s> DISCONNECTED after %d minutes. <%s>", playerName, authID, IPAddress, connectionTime, discReason);
    
    g_Player[client].Admin = false;
}

public Action Command_ConnectWatch(int client, int args)
{
    if (!IsClientInGame(client))
        return Plugin_Handled;
        
    if (!AreClientCookiesCached(client))
        ReplyToCommand(client, "[SM] Your coookies aren't cached yet. Please try again later...");
    else
        ShowCWMenu(client);
        
    return Plugin_Handled;
}

void ShowCWMenu(int client)
{
    Menu menu = new Menu(ShowCWMenu_Handler, MENU_ACTIONS_DEFAULT);
    menu.SetTitle("ConnectWatch Menu\n \nDisplay Settings:");
    
    char buffer[128];
    FormatEx(buffer, sizeof(buffer), "Display Chat Message: %s", g_Player[client].ChatMessage ? "Enabled" : "Disabled");
    menu.AddItem("cwChatToggle", buffer);
    FormatEx(buffer, sizeof(buffer), "Display Console Message: %s", g_Player[client].ConsoleMessage ? "Enabled" : "Disabled");
    menu.AddItem("cwConsoleToggle", buffer);
    
    menu.ExitButton = true;
    menu.Display(client, 30);
}

public int ShowCWMenu_Handler(Menu menu, MenuAction action, int client, int position)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[32];
            if (GetMenuItem(menu, position, info, sizeof(info)))
            {
                if (StrEqual(info, "cwChatToggle"))
                {
                    g_Player[client].ChatMessage = !g_Player[client].ChatMessage;
                    PrintToChat(client, " \x10[CW] \x05ConnectWatch chat message is now: %s", g_Player[client].ChatMessage ? "\x04Enabled" : "\x02Disabled");
                }
                
                if (StrEqual(info, "cwConsoleToggle"))
                {
                    g_Player[client].ConsoleMessage = !g_Player[client].ConsoleMessage;
                    PrintToChat(client, " \x10[CW] \x05ConnectWatch console message is now: %s", g_Player[client].ConsoleMessage ? "\x04Enabled" : "\x02Disabled");
                }
                
                SaveAndSetCookies(client);
                ShowCWMenu(client);
            }
        }
    }
}

// ----------------
// Stocks
// ----------------
stock bool IsClientAdmin(int client)
{
    if (CheckCommandAccess(client, "sm_cw", ADMFLAG_GENERIC))
        return true;
        
    return false;
}

stock void SaveAndSetCookies(int client)
{
    char cookie[3];
    FormatEx(cookie, sizeof(cookie), "%b%b", g_Player[client].ChatMessage, g_Player[client].ConsoleMessage);
    g_cConnectWatch.Set(client, cookie);
}

stock void Log(LOGTYPE logType, bool appendPrefix, const char[] message, any ...)
{
    char time[32], logMessage[512];
    FormatTime(time, sizeof(time), "%X", GetTime());
    VFormat(logMessage, sizeof(logMessage), message, 4);
    
    File logFile;
    if (logType == LOG_ADMIN)
        logFile = OpenFile(g_sAdminFilePath, "a+");
    else if (logType == LOG_PLAYER)
        logFile = OpenFile(g_sPlayerFilePath, "a+");
        
    if (appendPrefix)
        logFile.WriteLine("%s | %s", time, logMessage);
    else
        logFile.WriteLine("%s", logMessage);
        
    delete logFile;
}

stock void PrintMessageToAdmins(const char[] message, any ...)
{
    char printMessage[128];
    VFormat(printMessage, sizeof(printMessage), message, 2);
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !g_Player[i].Admin)
            continue;
            
        if (g_Player[i].ChatMessage)
            PrintToChat(i, "%s", printMessage);
            
        if (g_Player[i].ConsoleMessage)
            PrintToConsole(i, "%s", printMessage);
    }
}