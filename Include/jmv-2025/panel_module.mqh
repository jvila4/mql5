// panel_module.mqh
//
// Módulo de interfaz gráfica simple para el EA.
// Este módulo utiliza objetos de etiqueta (OBJ_LABEL) para dibujar un
// panel informativo en la esquina superior izquierda del gráfico.
// El panel muestra métricas clave del robot: número de operaciones
// diarias, drawdown actual, valores ATR y multiplicadores adaptativos,
// así como la última señal generada. Puede extenderse fácilmente
// para añadir más campos.

#ifndef __PANEL_MODULE_MQH
#define __PANEL_MODULE_MQH

// Nombre del objeto de panel
#define PANEL_LABEL_NAME "AdaptiveTradingPanel"

// Crea un objeto de etiqueta en el gráfico principal para usar como panel
void CreatePanel()
{
   // Asegurarse de que no exista ya
   if(ObjectFind(0, PANEL_LABEL_NAME) == -1)
   {
      // Crear una etiqueta invisible inicialmente
      ObjectCreate(0, PANEL_LABEL_NAME, OBJ_LABEL, 0, 0, 0);
      // Posición y estilo
      ObjectSetInteger(0, PANEL_LABEL_NAME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PANEL_LABEL_NAME, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, PANEL_LABEL_NAME, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, PANEL_LABEL_NAME, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, PANEL_LABEL_NAME, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, PANEL_LABEL_NAME, OBJPROP_BACK, true);
      ObjectSetInteger(0, PANEL_LABEL_NAME, OBJPROP_HIDDEN, true);
      ObjectSetString(0, PANEL_LABEL_NAME, OBJPROP_TEXT, "Panel inicializado\n");
   }
}

// Actualiza el contenido del panel con los datos proporcionados
void UpdatePanel(int tradesToday, double drawdownPct, double atrValue,
                 double aiMultSL, double aiMultTP, string lastSignal, double lastConfidence)
{
   // Construir texto multilinea
   string text = "Robot Intradía Adaptativo\n";
   text += "Operaciones hoy: " + IntegerToString(tradesToday) + "\n";
   text += "Drawdown: " + DoubleToString(drawdownPct, 2) + "%\n";
   text += "ATR (puntos): " + DoubleToString(atrValue, 1) + "\n";
   text += "Mult. SL: " + DoubleToString(aiMultSL, 2) + ", Mult. TP: " + DoubleToString(aiMultTP, 2) + "\n";
   text += "Última señal: " + lastSignal + " (confianza: " + DoubleToString(lastConfidence, 2) + ")";

   // Verificar que el objeto exista
   if(ObjectFind(0, PANEL_LABEL_NAME) != -1)
   {
      ObjectSetString(0, PANEL_LABEL_NAME, OBJPROP_TEXT, text);
   }
}

#endif // __PANEL_MODULE_MQH