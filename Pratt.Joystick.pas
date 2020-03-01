unit Pratt.Joystick;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  Winapi.mmsystem, Winapi.Messages,
  VCL.Controls;

const
  PJ_JOYSTICK_MOVE = WM_APP+1;
  PJ_BUTTON_UP     = WM_APP+2;
  PJ_BUTTON_DOWN   = WM_APP+3;
  PJ_STATUS_CHK    = WM_APP+4;

type
  TJoystickEvent = procedure(sender:TObject; X,Y, ButtonID:Integer) of object;
  TJSStatus = record
    X,Y:Integer;
    ButtonFlags:integer;
  end;

  TJoystick = class(TWinControl)
  private
    { Private declarations }
    fId:Integer;
    fDevCaps:JOYCAPS;
    fOnMove:TJoystickEvent;
    fOnBtnDown:TJoystickEvent;
    fOnBtnUp:TJoystickEvent;
    fCurrentState:JOYINFO;
    fDeltaStatus:JOYINFO;
    fPollPeriod:Integer;
    fDZX:integer;
    fDZY:Integer;

    Type
      TPollThread = class(TThread)
        private
          fOwner:TJoystick;
        protected
          procedure Execute;override;
        public
          constructor Create(AOwner:TJoystick);overload;
      end;

    function getMaxX:Integer;
    function getMaxY:Integer;
    function getMinX:Integer;
    function getMinY:Integer;
    function getX:Integer;
    function getY:Integer;
    class function getDevCount:Integer; static;
  protected
    { Protected declarations }
    { need to define Joystick move, Jostick button down and Joystick Button up
      message handlers}
    MX:TMutex;
    PollThread:TPollThread;
    procedure setStatus(var TheMsg:TMessage); message PJ_STATUS_CHK;
    procedure PJJoyButtonDown(var TheMsg:TMessage); message PJ_BUTTON_DOWN;
    procedure PJJoyMove(var TheMsg:TMessage); message PJ_JOYSTICK_MOVE;
    procedure PJJoyButtonUp (var TheMsg:TMessage); message PJ_BUTTON_UP;

  public
    { Public declarations }
    Constructor Create(AOwner:TComponent; DevID:Integer); reintroduce; overload;
    destructor Destroy; override;
    class property DeviceCount:Integer read getDevCount;
    property X:Integer read getX;
    property Y:Integer read GetY;
  published
    { Published declarations }
    {  Define event handlers for JoystickMove, ButtonDown and Button Up hamdlers}
    property OnBtnDown:TJoystickEvent read fOnBtnDown write fOnBtnDown;
    property OnBtnUp:TJoystickEvent read fOnBtnUp write fOnBtnUp;
    property OnMove:TJoystickEvent read fOnMove write fOnMove;
    property MaxX:Integer read getMAxX;
    property MaxY:INteger read getMaxY;
    property MinX:Integer read getMinX;
    property MinY:Integer read getMinY;
    property PollingPeriod:INteger read fPollPeriod write fPollPeriod;
    property Deadzone_X:Integer read fDZX write fDZY;
    property Deadzone_Y:Integer read fDZY write fDZY;
  end;


procedure Register;

implementation

  Constructor TJoystick.Create(AOwner: TComponent; DevID:Integer);
  begin
    inherited Create(AOwner);
    MX:=TMutex.Create;
      if Not Assigned(Parent) then
    if AOwner is TWinControl then
       Parent:=AOwner as TWinControl;
     HandleNeeded;
     fID := DevID;
     joyGetPos(fID,@fCurrentState);
     PollThread:=TPollThread.Create(self);
       joyGetDevCaps(0, @fDevCaps, sizeof(fDevCaps))
  end;

  destructor TJoystick.Destroy;
  begin
    self.PollThread.Terminate;
    MX.Destroy;
//    joyReleaseCapture(fID);
    inherited Destroy;
  end;

  class function TJoystick.getDevCount:Integer;
  begin
    result :=  joyGetNumDevs;
  end;

  procedure TJoystick.PJJoyButtonDown(var TheMsg: TMessage);
  var Btns:Integer;
  begin
    if Assigned(fOnBtnDown) then begin
      Btns := TheMsg.WParam and $f;
      fOnBtnDown(self, TheMsg.LParamLo, TheMsg.LParamHi, Btns);
    end;
  end;

  procedure TJoystick.PJJoyButtonUp(var TheMsg: TMessage);
  var Btns:Integer;
  begin
    if Assigned(fOnBtnUp)then begin
      Btns := TheMsg.WParam and $f;
      fOnBtnDown(self, TheMsg.LParamLo, TheMsg.LParamHi, Btns);
    end;
  end;

  procedure TJoystick.PJJoyMove(var TheMsg: TMessage);
  begin
    if Assigned(fOnMove) then
      fOnMove(self, TheMsg.LParamLo, TheMsg.LParamHi, 0);
  end;

function TJoystick.getMaxX;
  begin
    Result:=fDevCaps.wXmax;
  end;

  function TJoystick.getMaxY;
  begin
   Result:=fDevCaps.wXmax;
  end;

  function TJoystick.getMinX;
  begin
    Result := fDevCaps.wXmin;
  end;

  function TJoystick.getMinY: Integer;
  begin
    Result:=fDevCaps.wYmin;
  end;

  function TJoystick.getX: Integer;
  var Data:JoyInfo;
  begin
    JoyGetPos(fID, @Data);
    Result:=Data.wXpos;
  end;

  function TJoystick.getY: Integer;
  var Data:JoyInfo;
  begin
    JoyGetPos(fID, @Data);
    Result:=Data.wYpos;
  end;

  procedure TJoystick.setStatus(var TheMsg:TMessage);
  var Msg:TMessage;
      BtnsDn, BtnsUp, BtnsDelta:Integer;
  begin
  // No matter what status change occurs, we always send X and Y position
    Msg.LParamLo:=fDeltaStatus.wXpos;
    Msg.LParamHi:=fDeltaStatus.wYpos;
  // acquire the mutex for accessing fCurrentState and fDeltaStatus
    MX.Acquire;
//    determine if Joystick moved enough to generate a move event
    if (ABS(fDeltaStatus.wXpos - fCurrentState.wXpos-fDZX) > fDZX) or (ABS(fDeltaStatus.wYpos - fCurrentState.wYpos-fDZX) > fDZY) then begin
      Msg.Msg:=PJ_JOYSTICK_MOVE;
    end;
//  determine which buttons changed
    BtnsDelta:= fDeltaStatus.wButtons XOR fCurrentState.wButtons;
// determines HOW buttons have changed
    BtnsDn := BtnsDelta AND fDeltaStatus.wButtons;
    BtnsUp := BtnsDelta AND fCurrentState.wButtons;
    if BtnsDn > 0 then begin
      Msg.Msg := PJ_BUTTON_DOWN;
      Msg.WParam := BtnsDn;
    end;
    if BtnsUp > 0 then begin
      Msg.Msg := PJ_BUTTON_UP;
      Msg.WParam := BtnsUp;
    end;
// save the new data as current
    fCurrentState:=fDeltaStatus;
    MX.Release;
    Dispatch(Msg);
  end;

{ TJoystick.PollThread }

constructor TJoystick.TPollThread.Create(AOwner: TJoystick);
begin
  inherited Create;
  fOwner := Aowner;
end;

procedure TJoystick.TPollThread.Execute;
var Msg:TMessage;
begin
  while not self.terminated do begin
    fOwner.MX.Acquire;
    joyGetPos(FOwner.fID, @fOwner.fDeltaStatus);
    Msg.Msg:=PJ_STATUS_CHK;
    fowner.Dispatch(Msg);
    fOwner.MX.Release;
    sleep(fOwner.fPollPeriod);
  end;
end;

procedure Register;
begin
  RegisterComponents('Pratt', [TJoystick]);
end;

end.
