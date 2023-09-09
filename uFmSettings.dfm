object fmSettings: TfmSettings
  Left = 0
  Top = 0
  Caption = #1046#1091#1088#1085#1072#1083' '#1088#1072#1073#1086#1090#1099' reader'
  ClientHeight = 432
  ClientWidth = 483
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poDesigned
  OnClose = FormClose
  OnHide = FormHide
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object memResponse: TMemo
    Left = 0
    Top = 0
    Width = 483
    Height = 272
    Align = alClient
    Lines.Strings = (
      'memResponse')
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 272
    Width = 483
    Height = 160
    Align = alBottom
    ShowCaption = False
    TabOrder = 1
    object Label1: TLabel
      Left = 40
      Top = 22
      Width = 19
      Height = 13
      Caption = 'URL'
    end
    object Label2: TLabel
      Left = 40
      Top = 63
      Width = 69
      Height = 13
      Caption = #1044#1072#1085#1085#1099#1077' POST'
    end
    object Button1: TButton
      Left = 40
      Top = 112
      Width = 89
      Height = 33
      Caption = #1047#1072#1087#1088#1086#1089
      TabOrder = 0
      OnClick = Button1Click
    end
    object edData: TEdit
      Left = 40
      Top = 76
      Width = 393
      Height = 21
      TabOrder = 1
      Text = 'card_number=00FF0001&mac=EC-8E-B5-66-32-8C'
    end
    object edURL: TEdit
      Left = 40
      Top = 36
      Width = 393
      Height = 21
      TabOrder = 2
      Text = 'http://fd-node-vip.fdoctor.ru/queue_service/queue/kodos'
    end
  end
end
