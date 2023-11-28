bool CreateTrend(
    const string name,      // имя объекта
    datetime time1,           // время первой точки
    double price1,          // цена первой точки
    datetime time2,           // время второй точки
    double price2,          // цена второй точки
    const color clr = clrRed,        // цвет
    const int width = 1,           // толщина линии
    const int timeframes = OBJ_PERIOD_M1 | OBJ_PERIOD_M5 | OBJ_PERIOD_M15 | OBJ_PERIOD_M30 | OBJ_PERIOD_H1 | OBJ_PERIOD_H4,
    const long chartId = 0,         // ID графика
    const int windowNum = 0       // номер подокна
) {
//--- установим координаты точек привязки, если они не заданы
//   ChangeRectangleEmptyPoints(time1,price1,time2,price2);
//--- сбросим значение ошибки
   ResetLastError();
//--- создадим прямоугольник по заданным координатам
   if (!ObjectCreate(chartId, name, OBJ_TREND, windowNum, time1, price1, time2, price2)) {
      Print(__FUNCTION__, ": не удалось создать трендовую линию! Код ошибки = ", GetLastError());
      return false;
   }
//--- установим цвет прямоугольника
   ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
//--- установим толщину линий прямоугольника
   ObjectSetInteger(chartId, name, OBJPROP_WIDTH, width);
//--- установим стиль линий прямоугольника
   ObjectSetInteger(chartId, name, OBJPROP_STYLE, STYLE_SOLID);
//--- отобразим на переднем (false) или заднем (true) плане
   ObjectSetInteger(chartId, name, OBJPROP_BACK, true);
//--- включим (true) или отключим (false) режим выделения прямоугольника для перемещений
//--- при создании графического объекта функцией ObjectCreate, по умолчанию объект
//--- нельзя выделить и перемещать. Внутри же этого метода параметр selection
//--- по умолчанию равен true, что позволяет выделять и перемещать этот объект
   ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartId, name, OBJPROP_SELECTED, false);
//--- скроем (true) или отобразим (false) имя графического объекта в списке объектов
   ObjectSetInteger(chartId, name, OBJPROP_HIDDEN, true);
//--- установим видимость на таймфреймах
   ObjectSetInteger(chartId, name, OBJPROP_TIMEFRAMES, timeframes);

   ObjectSetInteger(chartId, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(chartId, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(chartId, name, OBJPROP_RAY, false);
//--- успешное выполнение
   return true;
}
