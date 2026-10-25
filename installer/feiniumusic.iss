; 飞牛音乐 Windows 安装版（Inno Setup 6）
;
; 由 .github/workflows/build-win-installer.yml 调用，版本号/产物目录通过 /D 传入：
;   iscc /DFEINIU_VERSION=1.6.9 /DFEINIU_RELEASE_DIR=<build Release 目录> feiniumusic.iss
;
; 关键点：
; 1. PrivilegesRequired=lowest —— 装进 %LOCALAPPDATA%，无需管理员权限（应用内可自行
;    静默升级，不会弹 UAC）。
; 2. CloseApplications=yes —— 应用内更新时安装器会自动关闭旧进程（应用自身也会先退出）。
; 3. 安装完成后自动拉起应用（静默升级同样拉起），实现“下载-安装-重启”闭环。
; 4. 不清理 feiniumusic_data/（用户账号、收藏、缓存），升级/卸载都不动数据。

#ifndef FEINIU_VERSION
  #define FEINIU_VERSION "0.0.0"
#endif
#ifndef FEINIU_RELEASE_DIR
  #define FEINIU_RELEASE_DIR "..\build\windows\x64\runner\Release"
#endif

#define MyAppName "飞牛音乐"
#define MyAppExeName "飞牛音乐.exe"
#define MyAppPublisher "kitblue"
#define MyAppURL "https://github.com/kitblue/FeiNiuMusic"
#define MyAppId "{{9C4E1B72-6D2A-4F6B-9A31-7C0B5D2E8F41}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#FEINIU_VERSION}
AppVerName={#MyAppName} {#FEINIU_VERSION}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Programs\FeiNiuMusic
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=FeiNiuMusic-v{#FEINIU_VERSION}-Windows-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
RestartApplications=no
AllowNoIcons=yes
UsedUserAreasWarning=no

[Languages]
#if FileExists(AddBackslash(CompilerPath) + "Languages\ChineseSimplified.isl")
Name: "cn"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#else
Name: "en"; MessagesFile: "compiler:Default.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"; Flags: checkedonce

[Files]
; Flutter Windows Release 全量产物（exe + data/ + 各 DLL，含 libmpv-2.dll）
Source: "{#FEINIU_RELEASE_DIR}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; 交互安装：结束页勾选启动
Filename: "{app}\{#MyAppExeName}"; Description: "立即启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
; 静默升级（应用内自动更新）：安装完成后直接拉起新版本
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: WizardSilent

[UninstallDelete]
; 仅清理安装产生的空目录，不触碰用户数据目录 feiniumusic_data
Type: dirifempty; Name: "{app}"
