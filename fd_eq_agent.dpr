program fd_eq_agent;

uses
  Forms,
  Windows,
  main in 'main.pas' {fmMain},
  UMacRead in 'UMacRead.pas',
  uFmSettings in 'uFmSettings.pas' {fmSettings};

{$R *.res}

begin

  Application.Initialize;
  Application.ShowMainForm := True;
  Application.MainFormOnTaskBar := False;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;

end.
