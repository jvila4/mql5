// indicator_module.mqh
//
// Biblioteca de indicadores y generación de señales para un EA intradía.
// Esta librería encapsula el cálculo de indicadores y la lógica de
// generación de señales para diferentes estrategias. Se puede ampliar
// añadiendo nuevos indicadores y estrategias sin modificar el EA.

#ifndef __INDICATOR_MODULE_MQH
#define __INDICATOR_MODULE_MQH

#include <Trade/Trade.mqh>

// Enumeración para los tipos de señal
enum SignalType
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
};

// Estructura que representa una señal de trading
struct Signal
{
   SignalType type;         // Tipo de señal (BUY/SELL/NONE)
   double     confidence;   // Confianza (0 a 1) basada en la fuerza de la señal
   double     entryPrice;   // Precio sugerido de entrada
   double     stopLossPts;  // Distancia de stop‑loss en puntos
   double     takeProfitPts;// Distancia de take‑profit en puntos
};

// Clase encargada de calcular indicadores y señales
class IndicatorModule
{
private:
   string symbol;   // Símbolo sobre el que se calculan las señales
   ENUM_TIMEFRAMES tf; // Timeframe (p.ej. PERIOD_M5)

public:
   // Constructor
   IndicatorModule(string _symbol, ENUM_TIMEFRAMES _tf)
   {
      symbol = _symbol;
      tf     = _tf;
   }

   // Devuelve el ATR actual (periodo 14) en puntos
   double GetATR(int atrPeriod=14)
   {
      double atrArray[];
      int copied = CopyBuffer(iATR(symbol, tf, atrPeriod), 0, 1, 1, atrArray);
      if(copied > 0)
         return atrArray[0] / _Point;
      return 0;
   }

   // Devuelve el valor actual de un EMA dado un periodo
   double GetEMA(int period)
   {
      double emaArray[];
      int copied = CopyBuffer(iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE), 0, 1, 1, emaArray);
      if(copied > 0)
         return emaArray[0];
      return 0;
   }

   // Devuelve el valor actual del RSI (periodo 14 por defecto)
   double GetRSI(int period=14)
   {
      double rsiArray[];
      int copied = CopyBuffer(iRSI(symbol, tf, period, PRICE_CLOSE), 0, 1, 1, rsiArray);
      if(copied > 0)
         return rsiArray[0];
      return 50.0;
   }

   // Devuelve el valor actual del Estocástico %K (14,3,3 por defecto)
   double GetStochastic(int kPeriod=14, int dPeriod=3, int slowing=3)
   {
      double kArray[];
      int copied = CopyBuffer(iStochastic(symbol, tf, kPeriod, dPeriod, slowing, MODE_SMA, PRICE_CLOSE), 0, 1, 1, kArray);
      if(copied > 0)
         return kArray[0];
      return 50.0;
   }

   // Devuelve el valor del ADX (periodo 14 por defecto)
   double GetADX(int period=14)
   {
      double adxArray[];
      int copied = CopyBuffer(iADX(symbol, tf, period), 0, 1, 1, adxArray);
      if(copied > 0)
         return adxArray[0];
      return 0;
   }

   // Devuelve la última lectura del MACD (histograma)
   double GetMACDHist(int fastPeriod=12, int slowPeriod=26, int signalPeriod=9)
   {
      double macdHistArray[];
      int copied = CopyBuffer(iMACD(symbol, tf, fastPeriod, slowPeriod, signalPeriod, PRICE_CLOSE), 2, 1, 1, macdHistArray);
      if(copied > 0)
         return macdHistArray[0];
      return 0;
   }

   // Estrategia Momo 5m: EMA20 y MACD
   Signal GetMomoSignal()
   {
      Signal signal;
      signal.type         = SIGNAL_NONE;
      signal.confidence   = 0;
      signal.entryPrice   = 0;
      signal.stopLossPts  = 0;
      signal.takeProfitPts= 0;

      // Obtener EMA 20 y MACD
      double ema20       = GetEMA(20);
      double macdHist    = GetMACDHist(12,26,9);
      double price       = SymbolInfoDouble(symbol, SYMBOL_BID);

      // Comprobar si cruzó la EMA
      // Para simplificar, se comparan el precio actual y la EMA
      if(price > ema20 && macdHist > 0)
      {
         // Señal de compra si se sitúa por encima de la EMA y MACD positivo
         signal.type        = SIGNAL_BUY;
         signal.confidence  = 0.7;
         signal.entryPrice  = price;
         signal.stopLossPts = 200; // valor base; el EA ajustará con ATR
         signal.takeProfitPts = 300;
      }
      else if(price < ema20 && macdHist < 0)
      {
         // Señal de venta si bajo EMA y MACD negativo
         signal.type        = SIGNAL_SELL;
         signal.confidence  = 0.7;
         signal.entryPrice  = price;
         signal.stopLossPts = 200;
         signal.takeProfitPts = 300;
      }

      return signal;
   }

   // Estrategia de cruces EMA (5/10) con filtros RSI y Estocástico
   Signal GetMovingAverageRSISignal()
   {
      Signal signal;
      signal.type         = SIGNAL_NONE;
      signal.confidence   = 0;
      signal.entryPrice   = 0;
      signal.stopLossPts  = 0;
      signal.takeProfitPts= 0;

      double ema5  = GetEMA(5);
      double ema10 = GetEMA(10);
      double rsi   = GetRSI(14);
      double sto   = GetStochastic(14,3,3);
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);

      // Cruce alcista y filtros
      if(ema5 > ema10 && rsi > 50 && sto > 50)
      {
         signal.type        = SIGNAL_BUY;
         signal.confidence  = 0.5;
         signal.entryPrice  = price;
         signal.stopLossPts = 150;
         signal.takeProfitPts = 250;
      }
      // Cruce bajista
      else if(ema5 < ema10 && rsi < 50 && sto < 50)
      {
         signal.type        = SIGNAL_SELL;
         signal.confidence  = 0.5;
         signal.entryPrice  = price;
         signal.stopLossPts = 150;
         signal.takeProfitPts = 250;
      }

      return signal;
   }

   // Estrategia de cruce adaptativo (AMA14/AMA50) con filtro RSI (14)
   Signal GetAdaptiveCrossoverRSISignal()
   {
      Signal signal;
      signal.type         = SIGNAL_NONE;
      signal.confidence   = 0;
      signal.entryPrice   = 0;
      signal.stopLossPts  = 0;
      signal.takeProfitPts= 0;

      // Utilizamos iAMA (Adaptive Moving Average)
      double amaFastArray[];
      double amaSlowArray[];
      int copiedFast = CopyBuffer(iAMA(symbol, tf, 14, 2, 30, PRICE_CLOSE), 0, 1, 1, amaFastArray);
      int copiedSlow = CopyBuffer(iAMA(symbol, tf, 50, 2, 30, PRICE_CLOSE), 0, 1, 1, amaSlowArray);
      if(copiedFast <= 0 || copiedSlow <= 0) return signal;
      double rsi = GetRSI(14);
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);

      if(amaFastArray[0] > amaSlowArray[0] && rsi > 50)
      {
         signal.type        = SIGNAL_BUY;
         signal.confidence  = 0.6;
         signal.entryPrice  = price;
         signal.stopLossPts = 180;
         signal.takeProfitPts = 280;
      }
      else if(amaFastArray[0] < amaSlowArray[0] && rsi < 50)
      {
         signal.type        = SIGNAL_SELL;
         signal.confidence  = 0.6;
         signal.entryPrice  = price;
         signal.stopLossPts = 180;
         signal.takeProfitPts = 280;
      }
      return signal;
   }

   // Combina varias estrategias y devuelve la señal con mayor confianza
   Signal GetCombinedSignal()
   {
      Signal sMomo    = GetMomoSignal();
      Signal sMA_RSI  = GetMovingAverageRSISignal();
      Signal sAMA_RSI = GetAdaptiveCrossoverRSISignal();

      Signal bestSignal = sMomo;
      if(sMA_RSI.confidence > bestSignal.confidence)
         bestSignal = sMA_RSI;
      if(sAMA_RSI.confidence > bestSignal.confidence)
         bestSignal = sAMA_RSI;

      return bestSignal;
   }
};

#endif // __INDICATOR_MODULE_MQH