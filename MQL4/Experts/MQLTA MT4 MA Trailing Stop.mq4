#property link          "https://www.earnforex.com/metatrader-expert-advisors/moving-average-trailing-stop/"
#property version       "1.02"
#property strict
#property copyright     "EarnForex.com - 2019-2025"
#property description   "This expert advisor will trail the stop-loss level based on the given moving average."
#property description   ""
#property description   "WARNING: You use this software at your own risk."
#property description   "The creator of this EA cannot be held responsible for any damage or loss."
#property description   ""
#property description   "Find more on www.EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

#include <MQLTA ErrorHandling.mqh>
#include <MQLTA Utils.mqh>

enum ENUM_CONSIDER
{
    All = -1,       //ALL ORDERS
    Buy = OP_BUY,   //BUY ONLY
    Sell = OP_SELL, //SELL ONLY
};

input string Comment_1 = "====================";  //Expert Advisor Settings
input int MAPeriod = 25;                          //Moving Average Period
input int MAShift = 0;                            //Moving Average Shift
input ENUM_MA_METHOD MAMethod = MODE_SMA;         //Moving Average Method
input ENUM_APPLIED_PRICE MAAppliedPrice = PRICE_CLOSE; //Moving Average Applied Price
input int Shift = 0;                              // Shift In The MA Value (0 = Current Candle)
input int ProfitPoints = 0;                       // Profit Points to Start Trailing (0 = ignore profit)
input string Comment_2 = "====================";  //Orders Filtering Options
input bool OnlyCurrentSymbol = true;              //Apply To Current Symbol Only
input ENUM_CONSIDER OnlyType = All;               //Apply To
input bool UseMagic = false;                      //Filter By Magic Number
input int MagicNumber = 0;                        //Magic Number (if above is true)
input bool UseComment = false;                    //Filter By Comment
input string CommentFilter = "";                  //Comment (if above is true)
input bool EnableTrailingParam = false;           //Enable Trailing Stop
input string Comment_3 = "====================";  //Notification Options
input bool EnableNotify = false;                  //Enable Notifications feature
input bool SendAlert = true;                      //Send Alert Notification
input bool SendApp = true;                        //Send Notification to Mobile
input bool SendEmail = true;                      //Send Notification via Email
input string Comment_3a = "===================="; //Graphical Window
input bool ShowPanel = true;                      //Show Graphical Panel
input string ExpertName = "MQLTA-MATS";           //Expert Name (to name the objects)
input int Xoff = 20;                              //Horizontal spacing for the control panel
input int Yoff = 20;                              //Vertical spacing for the control panel
input ENUM_BASE_CORNER ChartCorner = CORNER_LEFT_UPPER; // Chart Corner
input int FontSize = 10;                          // Font Size

int OrderOpRetry = 5;
double DPIScale; // Scaling parameter for the panel based on the screen DPI.
int PanelMovY, PanelLabX, PanelLabY, PanelRecX;
bool EnableTrailing = EnableTrailingParam;

int OnInit()
{
    CleanPanel();
    EnableTrailing = EnableTrailingParam;

    DPIScale = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;

    PanelMovY = (int)MathRound(20 * DPIScale);
    PanelLabX = (int)MathRound(150 * DPIScale);
    PanelLabY = PanelMovY;
    PanelRecX = PanelLabX + 4;

    if (ShowPanel) DrawPanel();

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    CleanPanel();
}

void OnTick()
{
    if (EnableTrailing) TrailingStop();
    if (ShowPanel) DrawPanel();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
        if (sparam == PanelEnableDisable)
        {
            ChangeTrailingEnabled();
        }
    }
    else if (id == CHARTEVENT_KEYDOWN)
    {
        if (lparam == 27)
        {
            if (MessageBox("Are you sure you want to close the MA Trailing Stop EA?", "Exit?", MB_YESNO) == IDYES)
            {
                ExpertRemove();
            }
        }
    }
}

double GetStopLossBuy(string symbol)
{
    double SLValue = iMA(symbol, PERIOD_CURRENT, MAPeriod, MAShift, MAMethod, MAAppliedPrice, Shift);
    return SLValue;
}

double GetStopLossSell(string symbol)
{
    double SLValue = iMA(symbol, PERIOD_CURRENT, MAPeriod, MAShift, MAMethod, MAAppliedPrice, Shift);
    return SLValue;
}

void TrailingStop()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false)
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - Unable to select the order - ", Error, " - ", ErrorText);
            continue;
        }
        if (OnlyCurrentSymbol && OrderSymbol() != Symbol()) continue;
        if (UseMagic && OrderMagicNumber() != MagicNumber) continue;
        if (UseComment && StringFind(OrderComment(), CommentFilter) < 0) continue;
        if (OnlyType != All && OrderType() != OnlyType) continue;

        string Instrument = OrderSymbol();
        double PointSymbol = SymbolInfoDouble(Instrument, SYMBOL_POINT);
        int eDigits = (int)SymbolInfoInteger(Instrument, SYMBOL_DIGITS);

        if (ProfitPoints > 0) // Check if there is enough profit points on this position.
        {
            if (((OrderType() == OP_BUY)  && ((OrderClosePrice() - OrderOpenPrice()) / PointSymbol < ProfitPoints)) ||
                ((OrderType() == OP_SELL) && ((OrderOpenPrice() - OrderClosePrice()) / PointSymbol < ProfitPoints))) continue;
        }

        double NewSL = 0;
        double NewTP = 0;
        double SLBuy = GetStopLossBuy(Instrument);
        double SLSell = GetStopLossSell(Instrument);
        if (SLBuy == 0 || SLSell == 0)
        {
            Print("Not enough historical data, please load more candles for The selected timeframe");
            return;
        }

        double TickSize = SymbolInfoDouble(Instrument, SYMBOL_TRADE_TICK_SIZE);
        if (TickSize > 0)
        {
            SLBuy = NormalizeDouble(MathRound(SLBuy / TickSize) * TickSize, eDigits);
            SLSell = NormalizeDouble(MathRound(SLSell / TickSize) * TickSize, eDigits);
        }

        double SLPrice = NormalizeDouble(OrderStopLoss(), eDigits);
        double Spread = SymbolInfoInteger(Instrument, SYMBOL_SPREAD) * PointSymbol;
        double StopLevel = SymbolInfoInteger(Instrument, SYMBOL_TRADE_STOPS_LEVEL) * PointSymbol;

        if (OrderType() == OP_BUY && SLBuy < SymbolInfoDouble(Instrument, SYMBOL_BID) - StopLevel)
        {
            if (SLBuy > SLPrice) // Modify only if new SL is above old SL.
            {
                ModifyOrder(SLBuy, OrderTakeProfit());
            }
        }
        else if (OrderType() == OP_SELL && SLSell > SymbolInfoDouble(Instrument, SYMBOL_ASK) + StopLevel)
        {
            if (SLSell < SLPrice || SLPrice == 0)
            {
                ModifyOrder(SLSell, OrderTakeProfit());
            }
        }
    }
}

void ModifyOrder(double SLPrice, double TPPrice)
{
    int eDigits = (int)SymbolInfoInteger(OrderSymbol(), SYMBOL_DIGITS);
    for (int i = 1; i <= OrderOpRetry; i++)
    {
        bool res = OrderModify(OrderTicket(), OrderOpenPrice(), SLPrice, TPPrice, 0, clrBlue);
        if (res)
        {
            Print("TRADE - UPDATE SUCCESS - Order ", OrderTicket(), ", new stop-loss: ", SLPrice);
            NotifyStopLossUpdate(SLPrice);
            return;
        }
        int Error = GetLastError();
        string ErrorText = GetLastErrorText(Error);
        Print("ERROR - UPDATE FAILED - error modifying order ", OrderTicket(), " return error: ", Error, " Open=", OrderOpenPrice(),
              " Old SL = ", OrderStopLoss(), " Old TP = ", OrderTakeProfit(),
              " New SL = ", SLPrice, " New TP = ", TPPrice, " Bid = ", SymbolInfoDouble(OrderSymbol(), SYMBOL_BID), " Ask = ", SymbolInfoDouble(OrderSymbol(), SYMBOL_ASK));
        Print("ERROR - ", ErrorText);
    }
}

void NotifyStopLossUpdate(double SLPrice)
{
    if (!EnableNotify) return;
    if (!SendAlert && !SendApp && !SendEmail) return;
    string EmailSubject = ExpertName + " " + OrderSymbol() + " Notification ";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n" + ExpertName + " Notification for " + OrderSymbol() + "\r\n";
    EmailBody += "Stop-loss for order " + IntegerToString(OrderTicket()) + " moved to " + DoubleToString(SLPrice, (int)SymbolInfoInteger(OrderSymbol(), SYMBOL_DIGITS));
    string AlertText = ExpertName + " - " + OrderSymbol() + " - stop-loss for order " + IntegerToString(OrderTicket()) + " was moved to " + DoubleToString(SLPrice, (int)SymbolInfoInteger(OrderSymbol(), SYMBOL_DIGITS));
    string AppText = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + " - " + ExpertName + " - " + OrderSymbol() + " - ";
    AppText += "stop-loss for order: " + IntegerToString(OrderTicket()) + " was moved to " + DoubleToString(SLPrice, (int)SymbolInfoInteger(OrderSymbol(), SYMBOL_DIGITS)) + "";
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
}

string PanelBase = ExpertName + "-P-BAS";
string PanelLabel = ExpertName + "-P-LAB";
string PanelEnableDisable = ExpertName + "-P-ENADIS";

void DrawPanel()
{
    int SignX = 1;
    int YAdjustment = 0;
    if ((ChartCorner == CORNER_RIGHT_UPPER) || (ChartCorner == CORNER_RIGHT_LOWER))
    {
        SignX = -1; // Correction for right-side panel position.
    }
    if ((ChartCorner == CORNER_RIGHT_LOWER) || (ChartCorner == CORNER_LEFT_LOWER))
    {
        YAdjustment = (PanelMovY + 2) * 2 + 1 - PanelLabY; // Correction for upper side panel position.
    }

    string PanelText = "MQLTA MATS";
    string PanelToolTip = "MA Trailing Stop Loss By MQLTA";
    CleanPanel();
    int Rows = 1;
    ObjectCreate(ChartID(), PanelBase, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_CORNER, ChartCorner);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_XDISTANCE, Xoff);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_YDISTANCE, Yoff + YAdjustment);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_BGCOLOR, clrWhite);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_HIDDEN, true);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_COLOR, clrBlack);

    DrawEdit(PanelLabel,
             Xoff + 2 * SignX,
             Yoff + 2,
             PanelLabX,
             PanelLabY,
             true,
             FontSize,
             PanelToolTip,
             ALIGN_CENTER,
             "Consolas",
             PanelText,
             false,
             clrNavy,
             clrKhaki,
             clrBlack);
    ObjectSetInteger(ChartID(), PanelLabel, OBJPROP_CORNER, ChartCorner);

    string EnableDisabledText = "";
    color EnableDisabledColor = clrNavy;
    color EnableDisabledBack = clrKhaki;
    if (EnableTrailing)
    {
        EnableDisabledText = "TRAILING ENABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkGreen;
    }
    else
    {
        EnableDisabledText = "TRAILING DISABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkRed;
    }

    DrawEdit(PanelEnableDisable,
             Xoff + 2 * SignX,
             Yoff + (PanelMovY + 1) * Rows + 2,
             PanelLabX,
             PanelLabY,
             true,
             FontSize,
             "Click to Enable or Disable the Trailing Stop Feature",
             ALIGN_CENTER,
             "Consolas",
             EnableDisabledText,
             false,
             EnableDisabledColor,
             EnableDisabledBack,
             clrBlack);
    ObjectSetInteger(ChartID(), PanelEnableDisable, OBJPROP_CORNER, ChartCorner);
    Rows++;

    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_XSIZE, PanelRecX);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_YSIZE, (PanelMovY + 1) * Rows + 3);
}

void CleanPanel()
{
    ObjectsDeleteAll(0, ExpertName + "-P-");
}

void ChangeTrailingEnabled()
{
    if (EnableTrailing == false)
    {
        if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
            MessageBox("Automated trading is disabled in the platform's options! Please enable it via Tools->Options->Expert Advisors.", "WARNING", MB_OK);
            return;
        }
        if (!MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
            MessageBox("Live Trading is disabled in the Position Sizer's settings! Please tick the Allow Live Trading checkbox on the Common tab.", "WARNING", MB_OK);
            return;
        }
        EnableTrailing = true;
    }
    else EnableTrailing = false;
    DrawPanel();
}
//+------------------------------------------------------------------+