unit uFmSettings;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls,HotLog, ExtCtrls,Synacode, cxGraphics, cxLookAndFeels,
  cxLookAndFeelPainters, Menus, cxButtons;

type
  TfmSettings = class(TForm)
    edURL: TEdit;
    edData: TEdit;
    Button1: TButton;
    memResponse: TMemo;
    Label1: TLabel;
    Label2: TLabel;
    pnlBottom: TPanel;
    cxButton1: TcxButton;
    procedure Button1Click(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormHide(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure cxButton1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  fmSettings: TfmSettings;

implementation
uses main;

{$R *.dfm}

procedure TfmSettings.Button1Click(Sender: TObject);
var
 response:String;
 ErrorCode:Integer;
begin

 fmMain.PostRequest(edURL.Text,edData.Text,response,ErrorCode);
 hLog.Add(DateTimeToStr(now) + ':response=' + response);
 hLog.Add('err_code=' + IntToStr(ErrorCode));
 if ErrorCode = 400 then
 begin
//  fmMain.ExecErrorJS('');
 // ������������� ���������� ��� �������
  // 11 - ������ ����� � ���� �� �������
  if Pos('"error_code": 11',response) > 0 then
   fmMain.ExecErrorJS('');

  // 19 - ��������� ����������� � �������
  if Pos('"error_code": 19',response) > 0 then
   fmMain.ExecErrorJS('doubleState');

  // 20 - ���������� ����� ��� 15 ��� �� ������ �������� ������� �����
  if Pos('"error_code": 20',response) > 0 then
   fmMain.ExecErrorJS('failStart');

  // 21 - ���������� � ������� ����� �������� �������� ������� �����
  if Pos('"error_code": 21',response) > 0 then
   fmMain.ExecErrorJS('endOff');
 end;


end;

procedure TfmSettings.cxButton1Click(Sender: TObject);
begin
 fmMain.ExecErrorJS('doubleState');
end;

procedure TfmSettings.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 Action := caHide;
end;

procedure TfmSettings.FormHide(Sender: TObject);
begin
 hLog.StopVisualFeedBack;
end;

procedure TfmSettings.FormShow(Sender: TObject);
var
 iPrimeMonitor:Integer;
begin

    iPrimeMonitor := Screen.PrimaryMonitor.MonitorNum;

    Self.Left := Screen.Monitors[iPrimeMonitor].Left +
                 Round((Screen.Monitors[iPrimeMonitor].Width - Self.Width)/2);
    Self.Top :=  Screen.Monitors[iPrimeMonitor].Top +
                 Round((Screen.Monitors[iPrimeMonitor].Height - Self.Height)/2);

    if not FindCmdLineSwitch('test',True) then
    begin
      pnlBottom.Visible := False;
    end;
end;

end.
