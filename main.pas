unit main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,Registry,
  Dialogs, ExtCtrls,  Menus, IniFiles,  VaClasses, VaComm,
  HotLog, httpsend,synacode, OleCtrls, SHDocVw,
  MSHTML, ShellAPI ;

const   //JS_DATA = '{"card_number": "%s","mac": "%s"}';}
        JS_DATA = 'card_number=%s&mac=%s';
        DEFAULT_URL = 'https://nfc.fdoctor.ru/eq_dev/queue/kodos';
        PORT_READ_DELAY = 1000; // Интервал следования байтов при считывании штрих-кода с датчика (ms)
type
  TfmMain = class(TForm)
    tiMain: TTrayIcon;
    pmMain: TPopupMenu;
    miReload: TMenuItem;
    N1: TMenuItem;
    miClose: TMenuItem;
    tmLoad: TTimer;
    miSetup: TMenuItem;
    Comm1: TVaComm;
    wbMain: TWebBrowser;
    tmHiddenLab: TTimer;
    procedure FormShow(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure miCloseClick(Sender: TObject);
    procedure miReloadClick(Sender: TObject);
    procedure tmLoadTimer(Sender: TObject);
    procedure miSetupClick(Sender: TObject);
    procedure Comm1RxChar(Sender: TObject; Count: Integer);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure wbMainBeforeNavigate2(ASender: TObject; const pDisp: IDispatch;
      var URL, Flags, TargetFrameName, PostData, Headers: OleVariant;
      var Cancel: WordBool);
    procedure wbMainNavigateError(ASender: TObject; const pDisp: IDispatch;
      var URL, Frame, StatusCode: OleVariant; var Cancel: WordBool);
    procedure wbMainDocumentComplete(ASender: TObject; const pDisp: IDispatch;
      var URL: OleVariant);
    procedure FormDestroy(Sender: TObject);
    procedure tmHiddenLabTimer(Sender: TObject);
  private
    Fmac: String;
    FURL: String;
    Fset_queue_url: String;
    Fcom_port_number: Integer;
//    CardNumber:String;
    buffer:String;
    Fdebug_log: Boolean;
    is_main_page_loaded:Boolean;
    SerialCommPortlist: TStringList;
    tckPortLastRead:Cardinal; // засечка последнего считанного символа
    CardNumberDec:Integer; // номер карты , считанный с reader-a
    FCardReaderType: String; // тип считывателя
    procedure Setmac(const Value: String);
    procedure SetURL(const Value: String);
    procedure SetPAtientMonitor;
    procedure Setset_queue_url(const Value: String);
    procedure Setcom_port_number(const Value: Integer);
    function GetCardCode(var CardCode: String): Boolean;
    procedure Setdebug_log(const Value: Boolean);
    procedure GetSerialPortsList;
    function GetCardCodeHiddenLab(var CardCode: String): Boolean;
    procedure SetCardReaderType(const Value: String);
   property mac:String read Fmac write Setmac;
   property URL:String read FURL write SetURL;
   property set_queue_url:String read Fset_queue_url write Setset_queue_url;
   property com_port_number:Integer read Fcom_port_number write Setcom_port_number;
   property debug_log:Boolean read Fdebug_log write Setdebug_log;
   property CardReaderType:String read FCardReaderType write SetCardReaderType;
   procedure set_queue(CardCode:String);
   procedure FixRegistry;
    { Private declarations }
  public
//   function PostRequest(url:String;js_data:String):string;
   function PostRequest(url, js_data: String;var response:String;var ErrorCode:Integer):boolean;
   procedure ExecErrorJS(sParam:String);
   procedure WriteLog(sMessage:String);
   procedure ClearBufferNoDigits();
    { Public declarations }
  end;

var
  fmMain: TfmMain;
  HookID: THandle;


function ExecuteScript(doc: IHTMLDocument2; script: string; language: string): Boolean;
function MouseProc(nCode: Integer; wParam, lParam: Longint): Longint; stdcall;

implementation
uses UMacRead,uFmSettings;

{$R *.dfm}

// чистка буфера СOM порта от всякого не нужного
procedure TfmMain.ClearBufferNoDigits;
var
  sTempBuffer:String;
  I:Integer;
begin
  sTempBuffer := '';
  for I := 1 to Length(buffer) do
   if buffer[i] in ['0'..'9'] then
     sTempBuffer := sTempBuffer + buffer[i];
  buffer := sTempBuffer;
end;

procedure TfmMain.Comm1RxChar(Sender: TObject; Count: Integer);
var
 s:String;
 sCard:String;
 res:Boolean;
begin
 s := String(Comm1.ReadText);
 buffer := buffer + s;
 tckPortLastRead := GetTickCount; // временная засечка последнего символа
 if UpperCase(Self.CardReaderType) = 'HIDDENLAB' then
  res := Self.GetCardCodeHiddenLab(sCard) // новый считыватель "HiddenLab q-485"
 else
  res := Self.GetCardCode(sCard); // старый считыватель

 if res then
 begin
  Comm1.PurgeRead;
  buffer := '';
  Self.set_queue(sCard); // отправляем запрос на постановку в очередь
 end;
end;

procedure TfmMain.ExecErrorJS(sParam:String);
var
 iDoc:IHTMLDocument2 ;
begin
 if sParam <> '' then
  sParam := 'eo.showError(''' + sParam + ''')'
 else
  sParam := 'eo.showError()';
 try
// Chromium.Browser.MainFrame.ExecuteJavaScript('eo.showError()','',0);
 wbMain.Document.QueryInterface(IHTMLDocument2, iDoc);
 if Assigned(iDoc) then
  ExecuteScript(iDoc, sParam, 'JavaScript')
 else
  hLog.Add('wbMain.Document.QueryInterface error...');
 except
   on E:Exception do
    hLog.Add(sParam + ': ' + E.Message);
 end;
end;

// Без этого ключа в реестре коспонент TWebBrowser использует только интерфейс IE7
// Независимо от того, какой установлен в системе по умолчанию
procedure TfmMain.FixRegistry;
var
 sFixFile:String;
 reg:TRegistry;
 bNeedImport:Boolean;
begin
 reg := TRegistry.Create;
 hLog.Add('Проверка наличия записи в реестре...');
 try
  bNeedImport := True;
  Reg.RootKey := HKEY_CURRENT_USER;

  if Reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION') then
   bNeedImport := not reg.ValueExists('fd_eq_agent.exe');

  if bNeedImport then
  begin
   sFixFile := ExtractFilePAth(Application.ExeName) + 'fix.reg';
   ShellExecute(0,nil,'regedit.exe',PChar('/s ' + sFixFile),nil,0);
   hLog.Add('Импорт "fix.reg" выполнен.');
  end
  else
    hLog.Add('Запись в реестре уже присутствует');

 finally
   reg.Free;
 end;
end;

procedure TfmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 Comm1.Close;
 if Assigned(fmSettings) then
 begin
  fmSettings.Close;
  fmSettings.Free;
 end;
 hLog.Add('Программа завершила работу.');
 hlog.Add(hLog.footer);
end;

procedure TfmMain.FormCreate(Sender: TObject);
var
 iSettings:TInifile;
begin
  iSettings := TInifile.Create(IncludeTrailingPathDelimiter(GetCurrentDir) + ChangeFileExt(ExtractFilename(Application.ExeName),'.ini'));
  try
   if iSettings.ReadBool('main','MacFromIni',False) then
    self.mac := iSettings.ReadString('main','MAC','')
   else
    self.mac := UMacRead.GetMACAddress;

   // чтобы иметь возможность тестировать страничку для монитора очереди
   if iSettings.ValueExists('main','URL_test') then
      FURL := iSettings.ReadString('main','URL_test','')
   else
      FURL := 'http://eqpd.fdoctor.ru/index_ie.html?mac=%mac%';
   FURL := StringReplace(FURL,'%mac%',self.mac,[rfReplaceAll]);
   set_queue_url := 'http://eqpd.fdoctor.ru/queue_service/queue/kodos';

   com_port_number := iSettings.ReadInteger('main','com_port',0);
   fdebug_log := iSettings.ReadBool('main','debug_log',false);

   // тип считывателя
   // default - EmMarine
   // HiddenLab
   Self.CardReaderType := iSettings.ReadString('main','reader','default');

   Self.FixRegistry;
   // отключим  у броузера контекстное меню и ролик мышки (zoom)
   HookID := SetWindowsHookEx(WH_MOUSE, MouseProc, 0, GetCurrentThreadId());
   tckPortLastRead := 0;
   CardNumberDec := 0;
  finally
   iSettings.Free;
  end;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  if HookID <> 0 then
    UnHookWindowsHookEx(HookID);
end;

procedure TfmMain.FormShow(Sender: TObject);
var
 sComPort:String;
begin
    // инициализация лог-файла
   hLog.hlWriter.hlFileDef.path :=  getcurrentdir;
   hLog.hlWriter.hlFileDef.gdgMax := 10;
   hLog.hlWriter.hlFileDef.UseFileSizeLimit := True;
   hLog.hlWriter.hlFileDef.LogFileMaxSize := TenMegabyte;
   hLog.SetErrorCaption('****** Error ******','*',True);
   hLog.SetErrorViewStyle(vsExtended);

   fmSettings := TfmSettings.Create(Application);
   hLog.DisplayFeedBackInto(fmSettings.memResponse);

   hLog.ScrollMemo(True);
   hLog.SetMemoLimit(1000);

   hLog.StartLogging;
   hLog.Add(hLog.header);


 Self.WindowState := wsMaximized;
 Self.BorderStyle := bsNone;
 ShowWindow(Application.Handle, SW_HIDE);
 Self.SetPAtientMonitor;

 hLog.Add('Параметры:');
 hLog.Add('MAC:' + Fmac);
 hLog.Add('URL монитора:' + FURL);
 hLog.Add('URL микросервиса:' + Fset_queue_url);
 hLog.Add('COM порт: COM' + IntToStr(com_port_number));

 // инициализуем и открываем COM порт
 if com_port_number > 0 then
 begin
  comm1.Parity := paNone;
  comm1.Stopbits := sb1;
  comm1.Databits := db8;
  comm1.Baudrate := br9600;
  Comm1.PortNum := com_port_number;
  try
   Comm1.Open ;
   hLog.Add('Порт COM' + IntToStr(com_port_number) + ' открыт.');
  except
   on E:Exception do
    hLog.Add('Ошибка открытия порта COM' + IntToStr(com_port_number) + ': ' + E.message);
  end;

 end;

 // Если не смогли открыть порт из ini файла, ищем первый установленный в системе
 if not Comm1.Active then
 begin
  Self.GetSerialPortsList;
  if Self.SerialCommPortlist.Count > 0 then
  begin
   while Self.SerialCommPortlist.Count > 0 do
   begin
     sComPort := Self.SerialCommPortlist[0];
     if Pos('COM',sComPort) > 0 then
     begin
       hLog.Add('Найден порт: ' + sComPort);
       sComPort := StringReplace(sComPort,'COM','',[rfReplaceAll]);
       if TryStrToInt(sComPort,Fcom_port_number) then
       begin
        try
         Comm1.PortNum := Fcom_port_number;
         Comm1.Open ;
         hLog.Add('Порт COM' + IntToStr(com_port_number) + ' открыт.');
        except
         on E:Exception do
          hLog.Add('Ошибка открытия порта COM' + IntToStr(com_port_number) + ': ' + E.message);
        end;
       end;
     end;
     if Comm1.Active then
      Break;
     SerialCommPortlist.Delete(0);
   end;

  end
  else
   hLog.Add('В системе не обнаружен ни один COM порт !');

 end;

 is_main_page_loaded := False;
 tmLoad.Enabled := True;

 end;

procedure TfmMain.miCloseClick(Sender: TObject);
begin
 hLog.Add('Программа завершила работу.');
 hlog.Add(hLog.footer);
 Application.Terminate;
end;

procedure TfmMain.miReloadClick(Sender: TObject);
begin
 is_main_page_loaded := False;
 tmLoad.Enabled := True;
end;

procedure TfmMain.miSetupClick(Sender: TObject);
begin
 if not Assigned(fmSettings) then
  fmSettings := TfmSettings.Create(Self);
 fmSettings.Showmodal;
end;

(*
function TfmMain.PostRequest(url, js_data: String;var response:String;var ErrorCode:Integer):boolean;
var
  json_strm  : TStringStream;
begin
 json_strm  := TStringStream.Create(js_data,1251);
 Result := False;
 if idHttp.Connected then
  IdHttp.Disconnect;
 try
 try
 Idhttp.HTTPOptions := [hoKeepOrigProtocol,hoForceEncodeParams];
 idHttp.ReadTimeout := 10000; // без этого дает Socket Error 10060
 idHttp.ConnectTimeout := 10000;

// IdSSLIOHandlerSocketOpenSSL1.SSLOptions.Method := sslvSSLv23;
// IdSSLIOHandlerSocketOpenSSL1.SSLOptions.Mode := sslmUnassigned;

 response := IdHttp.post(url, json_strm);
 ErrorCode := IdHTTP.ResponseCode;
 Result := True;
 except
   on E:EIdHTTPProtocolException do
   begin
    response := E.ErrorMessage;
    ErrorCode := E.ErrorCode;
   end;
   on E:Exception do
   begin
    response := E.Message;
    ErrorCode := 0;
   end;
 end;
  finally
    json_strm.free;
  end;
end;
*)

function TfmMain.PostRequest(url, js_data: String;var response:String;var ErrorCode:Integer):boolean;
var
  st: TMemoryStream;
  sl:TStringList;
begin
  Result := False;
  st:=TMemoryStream.Create;
  sl := TStringList.Create;
  try
    if HttpPostURL_1(url, js_data, st, ErrorCode) then
    begin
     st.Seek(0,soFromBeginning);
     sl.LoadFromStream(st);
     response := sl.Text;
     Result := True;
    end;
  finally
    st.free;
    sl.Free;
  end;

end;

procedure TfmMain.SetCardReaderType(const Value: String);
begin
  FCardReaderType := Value;
end;

procedure TfmMain.Setcom_port_number(const Value: Integer);
begin
  Fcom_port_number := Value;
end;

procedure TfmMain.Setdebug_log(const Value: Boolean);
begin
  Fdebug_log := Value;
end;

procedure TfmMain.Setmac(const Value: String);
begin
  Fmac := Value;
end;

procedure TfmMain.SetURL(const Value: String);
begin
  FURL := Value;
end;

procedure TfmMain.set_queue(CardCode:String);
var
 response:String;
 ErrorCode:Integer;
 sData:String;
 tmStart:Cardinal;
 iDuration:Integer;
begin
 hLog.Add(DateTimeToStr(Now) + ': постановка в очередь, карта = ' + CardCode);
 tmStart := GetTickCount;
// sData := Format(JS_DATA,[CardCode,Fmac]);
 sData := Format(JS_DATA,[EncodeURLElement(AnsiString(CardCode)),
                         EncodeURLElement(AnsiString(Fmac))]);
 Self.PostRequest(Fset_queue_url,sData,response,ErrorCode);
 iDuration := Round((GetTickCount - tmStart)/1000);
 if ErrorCode = 201 then
 begin
  if fdebug_log then
   hLog.Add('Response:' + response);
  hLog.Add('Response:201 ОК');
 end
 else if ErrorCode = 400 then
 begin
  hLog.Add('Response:' + response);
  hLog.Add('Error code = 400');
  // дополнительно обработать ряд статусов с ошибкой

  // 9 - выдача карты не зарегистрирована
  if Pos('"error_code": 9',response) > 0 then
   Self.ExecErrorJS('');

  // 11 - данная карта в базе не найдена
  if Pos('"error_code": 11',response) > 0 then
   Self.ExecErrorJS('');

  // 19 - повторная регистрация в очереди
  if Pos('"error_code": 19',response) > 0 then
   Self.ExecErrorJS('doubleState');

  // 20 - постановка ранее чем 15 мин до начала рабочего времени врача
  if Pos('"error_code": 20',response) > 0 then
   Self.ExecErrorJS('failStart');

  // 21 - постановка в очередь позже кончания рабочего времени врача
  if Pos('"error_code": 21',response) > 0 then
   Self.ExecErrorJS('endOff');
 end
 else if ErrorCode = 0 then
 begin
  hLog.Add('Response:' + response);
  hLog.Add('Error code = 0');
 end
 else
 begin
  if fdebug_log then
  begin
   hLog.Add('Response:' + response);
   hLog.Add('Error code = ' + IntToStr(ErrorCode));
  end;
 end;

 hLog.Add('Длительность запроса: ' + IntToStr(iDuration) + ' сек.');

end;

procedure TfmMain.tmHiddenLabTimer(Sender: TObject);
var
 sCard:String;
begin
if Self.GetCardCodeHiddenLab(sCard) then
  Self.set_queue(sCard);
end;

procedure TfmMain.tmLoadTimer(Sender: TObject);
var
 flags:OleVariant;
begin
 // отключаем использование кеша
 flags := navNoReadFromCache + navNoWriteToCache;
 if not is_main_page_loaded then
 begin
  tmLoad.Enabled := False;
  try
  wbMain.Navigate(Self.URL,flags);
  finally
   tmLoad.Enabled := True;
  end;
 end
 else
  tmLoad.Enabled := False;
end;

procedure TfmMain.wbMainBeforeNavigate2(ASender: TObject;
  const pDisp: IDispatch; var URL, Flags, TargetFrameName, PostData,
  Headers: OleVariant; var Cancel: WordBool);
begin
 hLog.Add(DateTimeToStr(now) + ' начало загрузки...');
end;

procedure TfmMain.wbMainDocumentComplete(ASender: TObject;
  const pDisp: IDispatch; var URL: OleVariant);
var
  CurWebrowser : IWebBrowser;
  TopWebBrowser: IWebBrowser;
begin { TForm1.WebBrowser1DocumentComplete }
  CurWebrowser := pDisp as IWebBrowser;
  TopWebBrowser := (ASender as TWebBrowser).DefaultInterface;
  if CurWebrowser = TopWebBrowser then
  begin
   hLog.Add(DateTimeToStr(now) + ' страница загружена.');
   is_main_page_loaded := True;
  end;
end;

procedure TfmMain.wbMainNavigateError(ASender: TObject; const pDisp: IDispatch;
  var URL, Frame, StatusCode: OleVariant; var Cancel: WordBool);
begin
 hLog.Add(DateTimeToStr(now) + ' ошибка при загрузке страницы: Status=' +
      IntToStr(StatusCode) );
end;

procedure TfmMain.WriteLog(sMessage: String);
begin
end;

procedure TfmMain.SetPatientMonitor;
var
 leftM:Integer;
 topM:Integer;
 iPrimeMonitor:Integer;
 iEQMonitor:Integer;
begin

  // выводим броузер на второй монитор (если таковой есть)
  if Screen.MonitorCount > 1 then
  begin
    iPrimeMonitor := Screen.PrimaryMonitor.MonitorNum;
    if iPrimeMonitor = 0 then
     iEQMonitor := 1
    else
     iEQMonitor := 0;
    leftM:=Screen.Monitors[iEQMonitor].Left  ;
    TopM:= Screen.Monitors[iEQMonitor].top;

    Self.Left:=leftM;
    Self.Top:=TopM;

    Self.Width := Screen.Monitors[iEQMonitor].Width;
    Self.Height := Screen.Monitors[iEQMonitor].Height;
  end;
end;

procedure TfmMain.Setset_queue_url(const Value: String);
begin
  Fset_queue_url := Value;
end;

function TfmMain.GetCardCode(var CardCode:String):Boolean;
var
    PosEM : integer;
    DecCode : string;
    cod1 : string;
    cod2 : string;
    sl:TStringList;
    i:Integer;
begin
     Result := False;
     PosEm := pos('No Card',buffer);
     if PosEm = 0 then
       Exit;

     sl := TStringlist.Create;
     try

     sl.text := buffer;
     for I := sl.count - 1 downto 1 do
      if Trim(sl[i]) = 'No Card' then
      begin
       CardCode := sl[i-1];
       Break;
      end;

     PosEM:=  Pos('Em-Marine',cardCode) ;

     if PosEM >0 then
     begin
       PosEM:=Pos(']',CardCode)  ;
       if PosEM > 0 then
       begin
        DecCode:=Copy(CardCode,PosEM+1) ;
        cod1:=Copy(decCode,0,Pos(',',decCode)-1 );
        cod2 :=Copy(decCode,Pos(',',decCode)+1);
        if (Cod1='') or (Cod2='') then
        begin
         hLog.Add(DateTimeToStr(Now())+' '+'Не разложилось на cod1: ' + cod1+' и cod2= '+cod2);
         buffer := '';
         exit;
        end;
        try
         cod1:=IntToHex(strToInt(cod1), 4);
         cod2:= IntToHex(strToInt(cod2), 4);
         CardCode := cod1 + cod2;
         hLog.Add('Считана карта Code=' + cod1 + cod2);
         Result := True;
        except
         hLog.Add(DateTimeToStr(Now())+' '+'Не преобразовалось в HEX из cod1: ' + cod1+' и cod2= '+cod2);
         buffer := '';
        end;
      end; // if PosEM >0 then
     end;

     finally
      if Assigned(sl) then
       sl.Free;
     end;
end;

// для новых считывателей HiddenLab
function TfmMain.GetCardCodeHiddenLab(var CardCode:String):Boolean;
var
 tckNow:Cardinal;
begin
     Result := False;
     tckNow := GetTickCount;
     //  Если приняли все символы кода - конвертим в HEX, чистим буфер и возвращаем CardCode
     if (CardNumberDec > 0) and ((tckNow - tckPortLastRead) > PORT_READ_DELAY) then
     begin
      try
        CardCode := IntToHex(CardNumberDec,8);
        tckPortLastRead := 0;
        CardNumberDec := 0;
        buffer := '';
        Result := True;
        tmHiddenLab.Enabled := False;
      except
        on E:Exception do
        begin
            hLog.Add(DateTimeToStr(Now()) + ': ' + E.Message);
            CardNumberDec := 0;
            tmHiddenLab.Enabled := False;
        end;
      end;
     end
     else
     begin // ждем следующие символы (только цифры)
      Self.ClearBufferNoDigits;
      if TryStrToInt(buffer, CardNumberDec) then
      begin
       if not tmHiddenLab.Enabled then
         tmHiddenLab.Enabled := True;
      end
      else
      begin // какой то мусор приняли , все отменяем
       tckPortLastRead := 0;
       CardNumberDec := 0;
       buffer := '';
       tmHiddenLab.Enabled := False;
      end;
     end;
end;

// список COM портов в системе
procedure TfmMain.GetSerialPortsList();
var
  Registry: TRegistry;
  i: integer;

begin
  if not Assigned(Self.SerialCommPortlist) then
   SerialCommPortlist := TStringList.Create;
  Registry := TRegistry.Create(KEY_READ);
    try
        SerialCommPortlist.Clear;
        Registry.RootKey := HKEY_LOCAL_MACHINE;
        if Registry.OpenKey('hardware\devicemap\serialcomm', false) then
         Registry.GetValueNames(SerialCommPortlist)
        else
         hLog.Add('GetSerialPortsList: не удалось прочитать список установленных в системе COM портов!');
        for i := 0 to SerialCommPortlist.Count-1 do
              SerialCommPortlist[i] := Registry.ReadString(SerialCommPortlist.Strings[i]);
    finally
      Registry.CloseKey;
      Registry.Free;
  end;
end;

function ExecuteScript(doc: IHTMLDocument2; script: string; language: string): Boolean;
var
  win: IHTMLWindow2;
  Olelanguage: Olevariant;
begin
  Result := False;
  if doc <> nil then
  begin
    try
      win := doc.parentWindow;
      if win <> nil then
      begin
        try
          Olelanguage := language;
          win.ExecScript(script, Olelanguage);
          Result := True;
        finally
          win := nil;
        end;
      end;
    finally
      doc := nil;
    end;
  end;
end;

//
function MouseProc(nCode: Integer; wParam, lParam: Longint): Longint; stdcall;
var
  szClassName: array[0..255] of Char;
const
  ie_name = 'Internet Explorer_Server';
begin
  case nCode < 0 of
    True:
      Result := CallNextHookEx(HookID, nCode, wParam, lParam)
      else
        case wParam of
          WM_RBUTTONDOWN,
          WM_RBUTTONUP,
          WM_MOUSEWHEEL,
          WM_MOUSEHWHEEL:
            begin
              GetClassName(PMOUSEHOOKSTRUCT(lParam)^.HWND, szClassName, SizeOf(szClassName));
              if lstrcmp(@szClassName[0], @ie_name[1]) = 0 then
                Result := HC_SKIP
              else
                Result := CallNextHookEx(HookID, nCode, wParam, lParam);
            end
            else
              Result := CallNextHookEx(HookID, nCode, wParam, lParam);
        end;
  end;
end;

end.
