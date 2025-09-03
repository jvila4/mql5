// AdaptiveTradingEA.mq5
//
// Expert Advisor de ejemplo que utiliza la biblioteca indicator_module.mqh
// para generar señales y abre/cierra operaciones de forma adaptativa.
// Incluye mecanismos básicos de gestión de riesgo, número de operaciones
// diarias y lectura de parámetros adaptativos desde un módulo externo.

#property strict
#include <Trade/Trade.mqh>
#include "indicator_module.mqh"
// Incluir módulo de panel para monitorización en el gráfico
#include "panel_module.mqh"

//=== Parámetros de usuario ===
input double   InpRiskPercent        = 1.0;     // Riesgo por operación (% del saldo)
input double   InpATRMultSL          = 2.0;     // Multiplicador de ATR para stop loss
input double   InpATRMultTP          = 3.0;     // Multiplicador de ATR para take profit
input int      InpMaxTradesPerDay    = 10;      // Máximo de operaciones diarias
input double   InpMaxDailyDrawdown   = 10.0;    // Máximo drawdown diario (% sobre pico)
input ulong    InpMagicNumber        = 123456;  // Magic Number
input string   InpAIParamFile        = "ai_params.csv"; // Archivo de parámetros IA

//=== Variables globales ===
CTrade          trade;
IndicatorModule *indicatorMod = NULL;

// Control de operaciones diarias y drawdown
int     tradesToday      = 0;
datetime lastTradeDay    = 0;
double  equityPeak       = 0.0;
bool    tradingPaused    = false;

// Variables para panel y monitorización
string lastSignalName    = "Ninguna";
double lastSignalConf    = 0.0;

// Parámetros adaptativos leídos de IA
double aiMultSL = 1.0;
double aiMultTP = 1.0;

// Función para leer parámetros de IA del archivo
void ReadAIParameters()
{
   // Por simplicidad, se espera que el archivo contenga dos números en la primera línea
   int fileHandle = FileOpen(InpAIParamFile, FILE_READ | FILE_CSV);
   if(fileHandle != INVALID_HANDLE)
   {
      if(!FileIsEnding(fileHandle))
      {
         aiMultSL = FileReadNumber(fileHandle);
         aiMultTP = FileReadNumber(fileHandle);
      }
      FileClose(fileHandle);
   }
}

// Calcular tamaño de lote en función del riesgo y el stop (en puntos)
double CalculateLotSize(double stopPoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   // Valor del punto para un lote estándar
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue == 0 || tickSize == 0) return 0.01;
   double pointValue = tickValue * (_Point / tickSize);
   double lotSize = riskAmount / (stopPoints * pointValue);
   // Ajustar a pasos permitidos
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lotSize = MathMax(minLot, MathMin(maxLot, NormalizeDouble(lotSize/lotStep, 0) * lotStep));
   return lotSize;
}

// Aplicar trailing stop a posiciones abiertas
void ApplyTrailingStop(int trailingPips)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
      // Sólo gestionar posiciones de este EA
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = 0;
      double newSL = 0;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         newSL = currentPrice - trailingPips * _Point;
         double currentSL = PositionGetDouble(POSITION_SL);
         if(newSL > currentSL)
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      }
      else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         newSL = currentPrice + trailingPips * _Point;
         double currentSL = PositionGetDouble(POSITION_SL);
         if(newSL < currentSL || currentSL == 0)
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      }
   }
}

// Función para reiniciar contadores diarios (llamada cada día en OnTimer)
void ResetDailyCounters()
{
   tradesToday   = 0;
   equityPeak    = AccountInfoDouble(ACCOUNT_EQUITY);
   tradingPaused = false;
}

// Inicialización del EA
int OnInit()
{
   indicatorMod = new IndicatorModule(_Symbol, PERIOD_M5);
   // Inicializar drawdown
   equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   lastTradeDay = TimeCurrent();
   EventSetTimer(60); // Llamar OnTimer cada 60 segundos

   // Crear panel de monitorización
   CreatePanel();
   return(INIT_SUCCEEDED);
}

// Desinicialización
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(indicatorMod != NULL)
      delete indicatorMod;
}

// Evento Timer: gestionar reset diario y leer parámetros IA
void OnTimer()
{
   datetime now = TimeCurrent();
   if(TimeDay(now) != TimeDay(lastTradeDay))
   {
      // Nuevo día: reiniciar contadores
      ResetDailyCounters();
      lastTradeDay = now;
   }
   // Leer parámetros IA periódicamente
   ReadAIParameters();
}

// Evento principal
void OnTick()
{
   // Verificar si el trading está pausado
   if(tradingPaused) return;

   // Actualizar equityPeak y drawdown
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity > equityPeak) equityPeak = currentEquity;
   double drawdownPct = (equityPeak - currentEquity) / equityPeak * 100.0;
   if(drawdownPct >= InpMaxDailyDrawdown)
   {
      tradingPaused = true;
      Print("Trading pausado por drawdown diario: ", drawdownPct, "%");
      return;
   }

   // Revisar número de operaciones diarias
   if(tradesToday >= InpMaxTradesPerDay)
      return;

   // Obtener señal combinada
   Signal sig = indicatorMod.GetCombinedSignal();
   if(sig.type == SIGNAL_NONE)
   {
      // Actualizar panel incluso si no hay señal nueva
      double atrPointsPanel = indicatorMod.GetATR(14);
      UpdatePanel(tradesToday, drawdownPct, atrPointsPanel, aiMultSL, aiMultTP,
                  lastSignalName, lastSignalConf);
      return;
   }

   // Almacenar última señal para el panel
   if(sig.type == SIGNAL_BUY)
   {
      lastSignalName = "Compra";
      lastSignalConf = sig.confidence;
   }
   else if(sig.type == SIGNAL_SELL)
   {
      lastSignalName = "Venta";
      lastSignalConf = sig.confidence;
   }

   // Calcular ATR actual (en puntos)
   double atrPoints = indicatorMod.GetATR(14);
   if(atrPoints <= 0) return;

   // Aplicar multiplicadores (Input * IA)
   double stopPoints = atrPoints * InpATRMultSL * aiMultSL;
   double tpPoints   = atrPoints * InpATRMultTP * aiMultTP;

   // Calcular lote
   double lot = CalculateLotSize(stopPoints);
   if(lot <= 0) return;

   // Determinar precios de stop y take
   double price    = sig.entryPrice;
   double stopLoss = 0;
   double takeProf = 0;

   if(sig.type == SIGNAL_BUY)
   {
      stopLoss = price - stopPoints * _Point;
      takeProf = price + tpPoints * _Point;
      // Abrir posición
      if(trade.Buy(lot, NULL, price, stopLoss, takeProf, "AdaptiveEA"))
      {
         tradesToday++;
      }
   }
   else if(sig.type == SIGNAL_SELL)
   {
      stopLoss = price + stopPoints * _Point;
      takeProf = price - tpPoints * _Point;
      if(trade.Sell(lot, NULL, price, stopLoss, takeProf, "AdaptiveEA"))
      {
         tradesToday++;
      }
   }

   // Aplicar trailing stop (ejemplo: 50% del stop original)
   int trailingPips = (int)(stopPoints * 0.5);
   ApplyTrailingStop(trailingPips);

   // Actualizar panel después de abrir/cerrar operaciones
   double atrForPanel = atrPoints;
   UpdatePanel(tradesToday, drawdownPct, atrForPanel, aiMultSL, aiMultTP,
               lastSignalName, lastSignalConf);
}