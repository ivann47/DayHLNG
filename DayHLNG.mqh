//
// DayHLNG.mqh
// Alexey Ivannikov (alexey.a.ivannikov@gmail.com)
//
//---------------------------------------------------------------------------------------------------------------------
#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include "CreateTrend.mqh"
#include "InfoPanel.mqh"
#include "StatData.mqh"

enum ENUM_ORDER_POSITION {
	ORDER_POSITION_SHADOW,
	ORDER_POSITION_BODY,
	ORDER_POSITION_CLOSE
};

struct EnvelopesValues {
	double lowerValue;
	double upperValue;
};

sinput uint i_magicNumber = 19700626;											// MagickNumber
input ENUM_ORDER_POSITION i_ordersPosition = ORDER_POSITION_SHADOW;	// Ориентир для установки ордеров
input uint i_ordersOffset = 0;													// Смещение для ордеров
sinput uint i_maxSpread = 30;								            		// Максимальный размер спреда
sinput uint i_delay = 10000;														// Задержка перед выставлением ордеров
input uint i_incrediblyDelay = 5000;											// Задержка для анализа запредельного состояния
input double i_incrediblyLimit = -1;											// Лимит запредельного состояния (отрицательное число)
input uint i_minBarSize = 0;														// Минимальный размер свечи
input uint i_maxBarSize = 100000;												// Максимальный размер свечи
input double i_riskLimit = 0.01;													// Допустимый риск (коэффициент)
input double i_fixedVolume = 0.01;												// Фиксированный лот
input uint i_takeProfit = 300;													// Фиксированный TP (пипсы)
input uint i_stopLoss = 200;														// Фиксированный SL (пипсы)
sinput bool i_useBreakeven = false;												// Включить перевод в безубыток
input uint i_breakevenTriggerLevel = 100;										// Уровень перевода позиции в безубыток (пипсы)
input uint i_breakevenValue = 10;												// Величина безубытка (пипсы)
sinput bool i_useFixedTrailing = false;										// Включить фиксированный Trailing Stop
input uint i_fixedTrailingTriggerLevel = 110;								// Уровень включения фиксированного Trailing Stop (пипсы)
input uint i_fixedTrailingValue = 100;											// Величина фиксированного Trailing Stop (пипсы)
sinput bool i_usePsarTrailing = true;											// Включить Trailing Stop по PSAR
input ENUM_TIMEFRAMES i_psarTrailingTimeframe = PERIOD_M15;				// Таймфрейм для Trailing Stop по PSAR
input double i_psarTrailingStep = 0.02;										// Шаг изменения цены для Trailing Stop по PSAR
input double i_psarTrailingMaxStep = 0.2;										// Максимальный шаг для Trailing Stop по PSAR
input uint i_maxOpenedPositions = 1;											// Максимальное количество открытых позиций
sinput string i_orderComment = "DayHLNG";										// Комментарий к ордерам
//input uint i_maxAliveTime = 0; 												// Максимальное время жизни прямых позиций в часах
//input uint i_maxAliveTimeReverse = 0;	 									// Максимальное время жизни реверсных позиций в часах
//sinput bool i_closeStraightPosion = false;									// Закрывать прямую позицию при открытии реверсной
input int i_period = 5;             											// Период усреднения
input ENUM_MA_METHOD i_method = MODE_EMA;    		   					// Метод усреднения
input ENUM_APPLIED_PRICE i_price = PRICE_CLOSE;			     				// Цена для расчёта
input int i_shift = 0;               											// Смещение
input double i_deviation = 1;              									// Отклонение границ от средней линии
sinput bool i_useInverse = true;													// Выставлять инверсные позиции
sinput bool i_showEnvelopes = true;												// Показывать значения Envelopes
sinput bool i_useLocking = false;						   			      // Использовать локирование
sinput bool i_useIncredibly = false;											// Использовать устранение запредельного состояния

class CDayHLNG {
public:
	CDayHLNG::CDayHLNG() {
		m_highTicket = m_lowTicket = 0;
		m_lastRateTime = 0;
		m_psarHandle = INVALID_HANDLE;
		m_envelopesHandle = INVALID_HANDLE;
	};

	int OnInit() {
		m_symbol = Symbol();

		if (!m_symbolInfo.Name(m_symbol)) return INIT_FAILED;

		m_trade.SetExpertMagicNumber(i_magicNumber);

		if (!checkInputParams()) return INIT_FAILED;

		m_lowOrderBarTime = m_highOrderBarTime = getLastRateTime();
		if (m_lowOrderBarTime == 0) return INIT_FAILED;

		if (!EventSetTimer(60)) return INIT_FAILED;

		m_incrediblyTime = getLastRateTime();
		m_newDay = false;
		m_startIncredibly = false;

		if (i_usePsarTrailing) {
			m_psarHandle = iSAR(m_symbol, i_psarTrailingTimeframe, i_psarTrailingStep, i_psarTrailingMaxStep);
			if (m_psarHandle == INVALID_HANDLE) {
				cleanup();
				return INIT_FAILED;
			}
		}

		m_envelopesHandle = iEnvelopes(m_symbol, PERIOD_D1, i_period, i_shift, i_method, i_price, i_deviation);
		if (m_envelopesHandle == INVALID_HANDLE) {
			cleanup();
			return INIT_FAILED;
		}

		if (i_showEnvelopes) drawEnvelopes(1);

		m_infoPanel.Create();
		UpdateInfoPanelData();
		m_infoPanel.Run();

		return INIT_SUCCEEDED;
	}

	void OnDeinit(const int reason) {
		cleanup();
		m_infoPanel.Destroy(reason);
	}

	void OnTick() {
		if (!checkOpenedPositions()) return;

		m_symbolInfo.Refresh();
		m_symbolInfo.RefreshRates();

		int positionsTotal = PositionsTotal();
		for (int i = positionsTotal - 1; i >= 0; i--) {
			if (checkPositionMagickNumber(i)) {
				ulong ticket = m_positionInfo.Ticket();
				double tp = m_positionInfo.TakeProfit();
				double sl = m_positionInfo.StopLoss();

				if (i_useBreakeven && checkCanSetBreakeven(ticket, sl)) {
					modifyPosition(ticket, sl, tp);
				}
				if (i_useFixedTrailing && checkCanFixedTrail(ticket, sl)) {
					modifyPosition(ticket, sl, tp);
				}
				if (i_usePsarTrailing) {
					if (checkCanPsarTrail(ticket, sl)) {
						modifyPosition(ticket, sl, tp);
					} else if (checkCanOpenReversePosition(m_positionInfo)) {
						openReversePosition(ticket);
					}
				}
			}
		}
	}

	void OnTimer() {
//		closeExpiredPositions();

		if (i_useIncredibly) Incredibly();

		if (i_useLocking) Locking();

		datetime t = getLastRateTime();

		if (i_showEnvelopes && m_lastDrawnEnvelopesTime < t) drawEnvelopes(1);

		if ((t == m_lowOrderBarTime && t == m_highOrderBarTime) || !checkAllowTrade(t)) return;

		removeClosedPositions();

//		m_reversePositionOpened = false;

		MqlRates rate;

		if (!getPrevDayRate(rate)) return;

		if (!checkRateLimits(rate)) return;

		m_symbolInfo.Refresh();
		m_symbolInfo.RefreshRates();

		EnvelopesValues ev;

		if (!getLastEnvelopes(ev)) return;

		if (t > m_highOrderBarTime) {
			if (rate.high > ev.upperValue) {
				if (i_useInverse) {
					PrintFormat("DEBUG: OnTimer: rate.high=%f, ev.upperValue=%f", rate.high, ev.upperValue);
					if (m_symbolInfo.Bid() > rate.high && openSellStopOrder(rate.high, true)) {
						m_highOrderBarTime = t;
					} else if (m_symbolInfo.Bid() < rate.high && openSellLimitOrder(rate.high, true)) {
						m_highOrderBarTime = t;
					}
				} else {
					m_highOrderBarTime = t;
				}
			} else if (openBuyStopOrder(getBuyPrice(rate))) {
				m_highOrderBarTime = t;
			}
		}

		if (t > m_lowOrderBarTime) {
			if (rate.low < ev.lowerValue) {
				if (i_useInverse) {
					PrintFormat("DEBUG: OnTimer: rate.low=%f, ev.lowerValue=%f", rate.low, ev.lowerValue);
					if (m_symbolInfo.Ask() < rate.low && openBuyStopOrder(rate.low, true)) {
						m_lowOrderBarTime = t;
					} else if (m_symbolInfo.Ask() > rate.low && openBuyLimitOrder(rate.low, true)) {
						m_lowOrderBarTime = t;
					}
				} else {
					m_lowOrderBarTime = t;
				}
			} else if (openSellStopOrder(getSellPrice(rate))) {
				m_lowOrderBarTime = t;
			}
		}
	}

	void  OnChartEvent(
		const int id,
   		const long& lparam,
   		const double& dparam,
   		const string& sparam
	) {
		m_infoPanel.OnEvent(id, lparam, dparam, sparam);
	}

	void OnTradeTransaction(
		const MqlTradeTransaction &trans,
		const MqlTradeRequest &request,
		const MqlTradeResult &result
	) {
//		PrintFormat("DEBUG: OnTradeTransaction: type=%d", trans.type);
		if (trans.type == TRADE_TRANSACTION_DEAL_ADD) {
			UpdateInfoPanelData();
		}
	}

private:
	string m_symbol;
	datetime m_highOrderBarTime;
	datetime m_lowOrderBarTime;
	ulong m_highTicket;
	ulong m_lowTicket;
	int m_psarHandle;
//	int m_maHandle;
	int m_envelopesHandle;
	datetime m_lastRateTime;
//	bool m_reversePositionOpened;
	ulong m_positionsWithReverse[];
	datetime m_lastDrawnEnvelopesTime;
	datetime m_incrediblyTime;
	bool m_newDay;
	bool m_startIncredibly;
	ulong m_ticket;
	bool m_executionIncredibly;


	CInfoPanel m_infoPanel;

	CTrade m_trade;
	CSymbolInfo m_symbolInfo;
	COrderInfo m_orderInfo;
	CPositionInfo m_positionInfo;
	CAccountInfo m_accountInfo;

//--------------------------------------------------------------------------/
//	Определение запредельного состояния
//--------------------------------------------------------------------------/
	bool Incredibly(){

		setTimeIncredibly();
		setStartIncredibly();
		executionIncredibly();

		return true;
	}
//--------------------------------------------------------------------------/

	void executionIncredibly() {
		if (m_executionIncredibly == false) return;

		m_trade.PositionClose(m_ticket);
		Print("закрыта позиция ticket  ",  m_ticket);
		m_executionIncredibly = false;

	}

//--------------------------------------------------------------------------/

	void setStartIncredibly() {
		if (m_startIncredibly == false) return;

		CPositionInfo pi;
		uint buyNumber = 0;
		uint sellNumber = 0;
		double point = Point();
		double profit = 0;
		double highPrice = 0;
		double lowPrice = 1000000;
		m_executionIncredibly = false;
		m_ticket = 0;

		int positionsTotal = PositionsTotal();
		for (int i = positionsTotal - 1; i >= 0; i--) {
			pi.SelectByIndex(i);
			if (pi.Symbol() != m_symbol || pi.Magic() != i_magicNumber) continue;
			if (pi.Time() > TimeCurrent() - 3600 * 24) {
//				Print("DEBUG: Позиция открыта менее суток назад");
				break;
			}

			ENUM_POSITION_TYPE type = pi.PositionType();
			double price = pi.PriceOpen();

			if (type == POSITION_TYPE_BUY) {
				buyNumber++;
				profit += pi.Profit();
				if (highPrice < price){
					highPrice = price;
					m_ticket = pi.Ticket();
				}
			}

			if (type == POSITION_TYPE_SELL) {
				sellNumber++;
				profit += pi.Profit();
				if (lowPrice > price) {
					lowPrice = price;
					m_ticket = pi.Ticket();
				}
			}
		}

		if ((buyNumber == i_maxOpenedPositions && sellNumber == 0) || (buyNumber == 0 && sellNumber == i_maxOpenedPositions)) {
			if (profit/(100000 * point) < i_incrediblyLimit) {
				Print("превышен лимит  ",  i_incrediblyLimit, "  profit = ", profit, "profit/point  ", profit/(100000 * point));
				m_executionIncredibly = true;
			}
		}

		m_startIncredibly = false;
	}

//--------------------------------------------------------------------------/

	void setTimeIncredibly() {
		if (m_lastRateTime > m_incrediblyTime) {
			m_newDay = true;
			m_incrediblyTime = m_lastRateTime + i_incrediblyDelay;
//			Print("m_newDay ", m_newDay, "m_incrediblyTime ", m_incrediblyTime);
		}

		if (m_newDay == true && TimeCurrent() > m_incrediblyTime) {
			m_startIncredibly = true;
			m_newDay = false;
//			Print("m_startIncredibly ", m_startIncredibly);
		}
	}

//--------------------------------------------------------------------------/
//  Локирование
//--------------------------------------------------------------------------/
	bool Locking() {
		CPositionInfo pi;
		ulong highTicket = 0;
		ulong lowTicket = 0;
		double highPrice = 0;
		double lowPrice = 1000000;

		int positionsTotal = PositionsTotal();
		for (int i = positionsTotal - 1; i >= 0; i--) {
			pi.SelectByIndex(i);
			if (pi.Symbol() != m_symbol || pi.Magic() != i_magicNumber) continue;
			ENUM_POSITION_TYPE type = pi.PositionType();
			double price = pi.PriceOpen();

			if (type == POSITION_TYPE_BUY && lowPrice > price) {
				lowPrice = price;
				lowTicket = pi.Ticket();
			}

			if (type == POSITION_TYPE_SELL && highPrice < price) {
				highPrice = price;
				highTicket = pi.Ticket();
			}
		}

		if (highPrice > lowPrice) {
			Print("Locking тикеты  ", highTicket, " ", lowTicket);

			m_trade.PositionCloseBy(highTicket, lowTicket);
//			m_trade.PositionClose(highTicket);
//			m_trade.PositionClose(lowTicket);
		}

		return true;
	}

//--------------------------------------------------------------------------/

	void UpdateInfoPanelData() {
		CStatData data;
		GetStat(data);
		m_infoPanel.SetInfo(data);
	}

	void GetStat(CStatData& data) {
		CPositionInfo pi;

		int totalPositions = PositionsTotal();

//		PrintFormat("DEBUG: PositionsTotal = %d", totalPositions);

		data.symbolCounters.direct = 0;
		data.symbolCounters.reverse = 0;
		data.symbolCounters.inverse = 0;
		data.totalCounters.direct = 0;
		data.totalCounters.reverse = 0;
		data.totalCounters.inverse = 0;

		for (int i = totalPositions - 1; i >= 0; i--) {
			pi.SelectByIndex(i);

			if (isPositionReverse(pi)) {
				data.totalCounters.reverse++;
				if (pi.Symbol() == m_symbol) data.symbolCounters.reverse++;
			} else if (isPositionInverse(pi)) {
				data.totalCounters.inverse++;
				if (pi.Symbol() == m_symbol) data.symbolCounters.inverse++;
			} else {
				data.totalCounters.direct++;
				if (pi.Symbol() == m_symbol) data.symbolCounters.direct++;
			}
		}
	}

	void drawEnvelopes(int pos = 0) {
		MqlRates rate;

		if (!getDayRate(rate, pos)) return;

		EnvelopesValues ev;

		if (!getEnvelopes(ev, pos)) return;

		string upperName = StringFormat("Envelope upper %d", rate.time);

		CreateTrend(upperName, rate.time, ev.upperValue, rate.time + 24 * 3600, ev.upperValue, clrRed, 3);

		string lowerName = StringFormat("Envelope lower %d", rate.time);

		CreateTrend(lowerName, rate.time, ev.lowerValue, rate.time + 24 * 3600, ev.lowerValue, clrForestGreen, 3);

		m_lastDrawnEnvelopesTime = rate.time;
	}

	void removeClosedPositions() {
		ulong buf[];

		uint size = m_positionsWithReverse.Size();

		for (uint i = 0; i < size; i++) {
			if (m_positionInfo.SelectByTicket(m_positionsWithReverse[i])) {
				uint s = buf.Size();
				ArrayResize(buf, s + 1, 1000);
				buf[s] = m_positionsWithReverse[i];
			}
		}

		ArrayCopy(m_positionsWithReverse, buf);
	}

	bool getDayRate(MqlRates& rate, int pos = 0) {
		MqlRates rates[1];

		if (CopyRates(m_symbol, PERIOD_D1, pos, 1, rates) == -1) {
			PrintFormat("ERROR: getPrevDayRate: CopyRates: %d", GetLastError());
			return false;
		}
		rate = rates[0];

		return true;
	}

	bool getPrevDayRate(MqlRates& rate) {
		return getDayRate(rate, 1);
	}

	bool getEnvelopes(EnvelopesValues& ev, int pos = 0) {
		double buffer[1];

		if (CopyBuffer(m_envelopesHandle, 0, pos, 1, buffer) == -1) {
			PrintFormat("ERROR: getEnvelopes: CopyBuffer: %d", GetLastError());
			return false;
		}
		ev.upperValue = buffer[0];

		if (CopyBuffer(m_envelopesHandle, 1, pos, 1, buffer) == -1) {
			PrintFormat("ERROR: getEnvelopes: CopyBuffer: %d", GetLastError());
			return false;
		}
		ev.lowerValue = buffer[0];

		return true;
	}

	bool getLastEnvelopes(EnvelopesValues& ev) {
		return getEnvelopes(ev, 1);
	}

	void cleanup() {
		EventKillTimer();

		if (m_psarHandle != INVALID_HANDLE) {
			IndicatorRelease(m_psarHandle);
			m_psarHandle = INVALID_HANDLE;
		}

		if (m_envelopesHandle != INVALID_HANDLE) {
			IndicatorRelease(m_envelopesHandle);
			m_envelopesHandle = INVALID_HANDLE;
		}

		m_lastRateTime = 0;
	}

	bool checkInputParams() {
		if (i_ordersPosition == ORDER_POSITION_CLOSE && (int)i_ordersOffset < m_symbolInfo.StopsLevel()) {
			return false;
		}
		return true;
	}

	bool getRateTime(datetime& time, int pos) {
		datetime buf[1];

		if (CopyTime(m_symbol, PERIOD_D1, pos, 1, buf) == -1) {
			PrintFormat("ERROR: getRateTime: CopyTime: %d", GetLastError());
			return false;
		}

		time = buf[0];

		return true;
	}

	datetime getLastRateTime() {
		datetime buf[1];
		if (CopyTime(m_symbol, PERIOD_D1, 0, 1, buf) == 1) {
			m_lastRateTime = buf[0];
		}
		return m_lastRateTime;
	}

	string getOrderComment(bool inverseOrder = false) {
		return inverseOrder ? getInverseOrderComment() : i_orderComment;
	}

	string getInverseOrderComment() {
		return StringFormat("%s inverse", i_orderComment);
	}

	string getReversePositionComment(ulong ticket) {
		return StringFormat("%s reverse %u", i_orderComment, ticket);
	}

	uint getOpenedPositionsNumber() {
		int positionsNumber = 0;
		for (int i = PositionsTotal(); i > 0; i--) {
			int positionIndex = i - 1;
			string symbol = PositionGetSymbol(positionIndex);
			if (symbol != m_symbol) continue;
			long magicNumber = PositionGetInteger(POSITION_MAGIC);
			if (magicNumber == i_magicNumber) positionsNumber++;
		}
		return positionsNumber;
	}

	bool isPositionReverse(CPositionInfo& pi) {
		return StringFind(pi.Comment(), "reverse") != -1;
	}

	bool isPositionInverse(CPositionInfo& pi) {
		return StringFind(pi.Comment(), "inverse") != -1;
	}
/*
	bool isPositionExpired(CPositionInfo& pi) {
		uint maxAliveTime = isPositionReverse(pi) ? i_maxAliveTimeReverse > 0 : i_maxAliveTime;

		if (maxAliveTime == 0) return false;

		datetime openTime = m_positionInfo.Time();
		datetime now = TimeCurrent();
		return now - openTime >= maxAliveTime * 3600;
	}

	void closeExpiredPositions() {
		int positionsTotal = PositionsTotal();
		for (int i = positionsTotal - 1; i >= 0; i--) {
			if (!checkPositionMagickNumber(i)) continue;
			CPositionInfo pi;
			pi.SelectByIndex(i);
			if (isPositionExpired(pi)) {
				m_trade.PositionClose(pi.Ticket());
			}
		}
	}
*/
	bool checkAllowTrade(datetime t) {
		return getOpenedPositionsNumber() < i_maxOpenedPositions &&
			m_symbolInfo.Spread() < (int) i_maxSpread &&
			TimeCurrent() - t > i_delay;
	}

	bool checkRateLimits(const MqlRates& rate) {
		uint delta = (int)MathFloor((rate.high - rate.low) / m_symbolInfo.Point());
		if (delta < i_minBarSize) {
			PrintFormat("NOTICE: Bar is less than limit: bar=%d, limit=%d", delta, i_minBarSize);
			return false;
		} else if (delta > i_maxBarSize) {
			PrintFormat("NOTICE: Bar is greater than limit: bar=%d, limit=%d", delta, i_maxBarSize);
			return false;
		}
		return true;
	}

	bool checkOpenedPositions() {
		return m_positionInfo.SelectByMagic(m_symbol, i_magicNumber);
	}

	bool checkPositionMagickNumber(int positionIndex) {
		return m_positionInfo.SelectByIndex(positionIndex) && m_positionInfo.Magic() == i_magicNumber;
	}

	void deleteAllOrders() {
		int ordersTotal = OrdersTotal();
		for (int i = ordersTotal - 1; i >=0; i--) {
			if (m_orderInfo.SelectByIndex(i) && m_orderInfo.Magic() == i_magicNumber) {
				m_trade.OrderDelete(m_orderInfo.Ticket());
			}
		}
		m_highTicket = m_lowTicket = 0;
	}

	double adjustVolume(double volume) {
    	return MathRound(volume / m_symbolInfo.LotsMin()) * m_symbolInfo.LotsMin();
	}

	double calcVolume(double price, double sl, ENUM_ORDER_TYPE orderType) {
		double loss = m_accountInfo.OrderProfitCheck(m_symbol, orderType, 1, price, sl);
//		PrintFormat("DEBUG: calcVolume: price=%f, sl=%f, loss=%f", price, sl, loss);
    	return adjustVolume(m_accountInfo.Balance() * i_riskLimit / MathAbs(loss));
	}

	double getBodyTopPrice(const MqlRates& rate) {
		return rate.close > rate.open ? rate.close : rate.open;
	}

	double getBodyBottomPrice(const MqlRates& rate) {
		return rate.close > rate.open ? rate.open : rate.close;
	}

	double getBuyPrice(const MqlRates& rate) {
		double price = i_ordersPosition == ORDER_POSITION_SHADOW ?
			rate.high :
			i_ordersPosition == ORDER_POSITION_CLOSE ?
				rate.close :
				getBodyTopPrice(rate);
		return price + (i_ordersOffset + m_symbolInfo.Spread()) * m_symbolInfo.Point();
	}

	double getSellPrice(const MqlRates& rate) {
		double price = i_ordersPosition == ORDER_POSITION_SHADOW ?
			rate.low :
			i_ordersPosition == ORDER_POSITION_CLOSE ?
				rate.close :
				getBodyBottomPrice(rate);
		return price - i_ordersOffset * m_symbolInfo.Point();
	}

	bool openBuyStopOrder(double price, bool inverseOrder = false) {
		static bool priceWarningPrinted = false;
		static bool volumeWargingPrinted = false;

		if (price < m_symbolInfo.Ask()) {
			if (!priceWarningPrinted) {
				PrintFormat("WARNING: price is less than Ask price: %f < %f", price, m_symbolInfo.Ask());
				priceWarningPrinted = true;
			}
			return false;
		}
		priceWarningPrinted = false;

		double tp = getTP(price, ORDER_TYPE_BUY);
		double sl = getSL(price, ORDER_TYPE_BUY);
		double volume = i_fixedVolume > 0 ? i_fixedVolume : calcVolume(price, sl, ORDER_TYPE_BUY);
		if (volume < m_symbolInfo.LotsMin()) {
			if (!volumeWargingPrinted) {
				PrintFormat("WARNING: Buy volume too small: %f", volume);
				volumeWargingPrinted = true;
			}
			return false;
		}
		volumeWargingPrinted = false;

		bool success = m_trade.BuyStop(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY, 0, getOrderComment(inverseOrder));
		if (!success || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}
		m_highTicket = m_trade.ResultOrder();
		return true;
	}

	bool openBuyLimitOrder(double price, bool inverseOrder = false) {
		static bool priceWarningPrinted = false;
		static bool volumeWargingPrinted = false;

		if (price > m_symbolInfo.Ask()) {
			if (!priceWarningPrinted) {
				PrintFormat("WARNING: price is more than Ask price: %f < %f", price, m_symbolInfo.Ask());
				priceWarningPrinted = true;
			}
			return false;
		}
		priceWarningPrinted = false;

		double tp = getTP(price, ORDER_TYPE_BUY);
		double sl = getSL(price, ORDER_TYPE_BUY);
		double volume = i_fixedVolume > 0 ? i_fixedVolume : calcVolume(price, sl, ORDER_TYPE_BUY);
		if (volume < m_symbolInfo.LotsMin()) {
			if (!volumeWargingPrinted) {
				PrintFormat("WARNING: Buy volume too small: %f", volume);
				volumeWargingPrinted = true;
			}
			return false;
		}
		volumeWargingPrinted = false;

		bool success = m_trade.BuyLimit(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY, 0, getOrderComment(inverseOrder));
		if (!success || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}
		m_highTicket = m_trade.ResultOrder();
		return true;
	}

	bool openSellStopOrder(double price, bool inverseOrder = false) {
		static bool priceWarningPrinted = false;
		static bool volumeWargingPrinted = false;

		if (price > m_symbolInfo.Bid()) {
			if (!priceWarningPrinted) {
				PrintFormat("WARNING: price is more than Bid price: %f > %f", price, m_symbolInfo.Bid());
				priceWarningPrinted = true;
			}
			return false;
		}
		priceWarningPrinted = false;

		double tp = getTP(price, ORDER_TYPE_SELL);
		double sl = getSL(price, ORDER_TYPE_SELL);
		double volume = i_fixedVolume > 0 ? i_fixedVolume : calcVolume(price, sl, ORDER_TYPE_SELL);
		if (volume < m_symbolInfo.LotsMin()) {
			if (!volumeWargingPrinted) {
				PrintFormat("WARNING: Sell volume too small");
				volumeWargingPrinted = true;
			}
			return true;
		}
		volumeWargingPrinted = false;

		bool success = m_trade.SellStop(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY, 0, getOrderComment(inverseOrder));
		if (!success || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}
		m_lowTicket = m_trade.ResultOrder();
		return true;
	}

	bool openSellLimitOrder(double price, bool inverseOrder = false) {
		static bool priceWarningPrinted = false;
		static bool volumeWargingPrinted = false;

		if (price < m_symbolInfo.Bid()) {
			if (!priceWarningPrinted) {
				PrintFormat("WARNING: price is less than Bid price: %f > %f", price, m_symbolInfo.Bid());
				priceWarningPrinted = true;
			}
			return false;
		}
		priceWarningPrinted = false;

		double tp = getTP(price, ORDER_TYPE_SELL);
		double sl = getSL(price, ORDER_TYPE_SELL);
		double volume = i_fixedVolume > 0 ? i_fixedVolume : calcVolume(price, sl, ORDER_TYPE_SELL);
		if (volume < m_symbolInfo.LotsMin()) {
			if (!volumeWargingPrinted) {
				PrintFormat("WARNING: Sell volume too small");
				volumeWargingPrinted = true;
			}
			return true;
		}
		volumeWargingPrinted = false;

		bool success = m_trade.SellLimit(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY, 0, getOrderComment(inverseOrder));
		if (!success || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}
		m_lowTicket = m_trade.ResultOrder();
		return true;
	}

	bool checkBullBar(const MqlRates& rate) {
		return rate.open < rate.close;
	}

	bool checkSlAndTp(ulong ticket, double sl, double tp) {
		CPositionInfo pi;
		pi.SelectByTicket(ticket);
		double price = pi.PriceCurrent();

		CSymbolInfo si;
		si.Name(pi.Symbol());

		double point = si.Point();

		bool result = MathAbs(pi.StopLoss() - sl) <= point && MathAbs(pi.TakeProfit() - tp) <= point ?
				false :
				pi.PositionType() == POSITION_TYPE_BUY ?
						price > sl && price < tp :
						price < sl && price > tp;

		return result;
	}

	bool modifyPosition(ulong ticket, double sl, double tp) {
		if (!checkSlAndTp(ticket, sl, tp)) {
			return false;
		}

		MqlTradeRequest request;
		MqlTradeResult result;
		ZeroMemory(request);
		ZeroMemory(result);
		request.action = TRADE_ACTION_SLTP;
		request.symbol = m_symbol;
		request.sl = sl;
		request.tp = tp;
		request.position = ticket;
		request.magic = i_magicNumber;

		return OrderSend(request, result);
	}

	int calcPoints(double pricesDelta) {
		return (int)(pricesDelta / m_symbolInfo.Point());
	}

	double calcPriceDelta(int points) {
		return points * m_symbolInfo.Point();
	}

	bool checkCanSetBreakeven(ulong ticket, double& sl) {
		if (i_breakevenTriggerLevel == 0) return false;
		CPositionInfo pi;
		pi.SelectByTicket(ticket);
		ENUM_POSITION_TYPE type = pi.PositionType();
		double openPrice = pi.PriceOpen(),
			   currentPrice = pi.PriceCurrent();
		sl = pi.StopLoss();

		if (type == POSITION_TYPE_BUY && calcPoints(sl - openPrice) < (int)i_breakevenValue && calcPoints(currentPrice - openPrice) >= (int)i_breakevenTriggerLevel) {
			sl = openPrice + calcPriceDelta(i_breakevenValue);
			return true;
		} else if (type == POSITION_TYPE_SELL && calcPoints(openPrice - sl) < (int)i_breakevenValue && calcPoints(openPrice - currentPrice) >= (int)i_breakevenTriggerLevel) {
			sl = openPrice - calcPriceDelta(i_breakevenValue);
			return true;
		}
		return false;
	}

	bool checkCanFixedTrail(ulong ticket, double &sl) {
		if (i_fixedTrailingValue == 0) return false;
		CPositionInfo pi;
		pi.SelectByTicket(ticket);
		ENUM_POSITION_TYPE type = pi.PositionType();
		double openPrice = pi.PriceOpen(),
			   currentPrice = pi.PriceCurrent();
		sl = pi.StopLoss();

		double trailLevelDelta = i_fixedTrailingTriggerLevel * m_symbolInfo.Point();
		double trailDelta = i_fixedTrailingValue * m_symbolInfo.Point();

		if (type == POSITION_TYPE_BUY && currentPrice - trailLevelDelta > openPrice && currentPrice - trailDelta > sl) {
			sl = currentPrice - trailDelta;
			return true;
		} else if (type == POSITION_TYPE_SELL && currentPrice + trailLevelDelta < openPrice && currentPrice + trailDelta < sl) {
			sl = currentPrice + trailDelta;
			return true;
		}
		return false;
	}

	bool checkCanPsarTrail(ulong ticket, double &sl) {
		CPositionInfo pi;
		pi.SelectByTicket(ticket);
		ENUM_POSITION_TYPE type = pi.PositionType();
		double openPrice = pi.PriceOpen(),
			   currentPrice = pi.PriceCurrent();
		sl = pi.StopLoss();

		double buffer[2];
		int n = CopyBuffer(m_psarHandle, 0, 0, 2, buffer);
		if (n == -1) return false;

		if ((type == POSITION_TYPE_BUY && buffer[1] > buffer[0] && buffer[0] > openPrice && buffer[0] < currentPrice && buffer[0] > sl) ||
		    (type == POSITION_TYPE_SELL && buffer[1] < buffer[0] && buffer[0] < openPrice && buffer[0] > currentPrice && buffer[0] < sl)) {
			sl = buffer[0];
			return true;
		}
		return false;
	}

	bool isPositionInBreakeven(CPositionInfo& pi) {
		ENUM_POSITION_TYPE type = pi.PositionType();
		double price = pi.PriceOpen();
		double sl = pi.StopLoss();

		return (type == POSITION_TYPE_BUY && price < sl) ||
			(type == POSITION_TYPE_SELL && price > sl);
	}

	bool isPositionProfitable(CPositionInfo& pi) {
		ENUM_POSITION_TYPE type = pi.PositionType();
		double priceOpen = pi.PriceOpen();
		double priceCurrent = pi.PriceCurrent();

		return (type == POSITION_TYPE_BUY && priceOpen < priceCurrent) ||
			(type == POSITION_TYPE_SELL && priceOpen > priceCurrent);
	}

	bool checkPsarInversionOccured(CPositionInfo& pi, int psarHandle) {
		double buffer[2];

		int n = CopyBuffer(psarHandle, 0, 0, 2, buffer);
		if (n == -1) return false;

		double price = pi.PriceCurrent();

		ENUM_POSITION_TYPE type = pi.PositionType();

		return (type == POSITION_TYPE_BUY && buffer[0] < price && price < buffer[1]) ||
			   (type == POSITION_TYPE_SELL && buffer[0] > price && price > buffer[1]);
	}

	bool checkPriceOutOfRange() {
		m_symbolInfo.Refresh();
		m_symbolInfo.RefreshRates();

		EnvelopesValues ev;

		getLastEnvelopes(ev);

		return (m_symbolInfo.Ask() >= ev.upperValue) || (m_symbolInfo.Bid() <= ev.lowerValue);
	}

	bool isReversePositionOpened(CPositionInfo& pi) {
		uint size = m_positionsWithReverse.Size();

		for (uint i = 0; i < size; i++) {
			if (pi.Ticket() == m_positionsWithReverse[i]) {
				return true;
			}
		}

		return false;
	}

	bool checkCanOpenReversePosition(CPositionInfo& pi) {
		if (isPositionInverse(pi) || isPositionReverse(pi)) {
			return false;
		}

		if (pi.Time() + 3600 * 24 < TimeCurrent()) {
//			Print("DEBUG: Позиция открыта раньше начала текущих суток");
			return false;
		}

		if (isPositionInBreakeven(pi)) {
//			Print("DEBUG: Позиция в безубытке");
			return false;
		}

		if (isPositionProfitable(pi)) {
			return false;
		}

		if (!checkPsarInversionOccured(pi, m_psarHandle)) {
//			Print("DEBUG: Инверсия параболика не произошла");
			return false;
		}

		if (checkPriceOutOfRange()) {
			return false;
		}

		if (isReversePositionOpened(pi)) {
//			Print("DEBUG: Реверсная позиция уже открывалась для этой позиции");
			return false;
		}

		return true;
	}

	ENUM_ORDER_TYPE getReverseOrderType(ENUM_POSITION_TYPE type) {
		if (type == POSITION_TYPE_BUY) {
			return ORDER_TYPE_SELL;
		} else if (type == POSITION_TYPE_SELL) {
			return ORDER_TYPE_BUY;
		}
		return -1;
	}

	double getMarketPrice(ENUM_ORDER_TYPE type) {
		if (type == ORDER_TYPE_BUY) {
			return m_symbolInfo.Ask();
		} else if (type == ORDER_TYPE_SELL) {
			return m_symbolInfo.Bid();
		}
		return -1;
	}

	double getTP(double price, ENUM_ORDER_TYPE type) {
		double delta = calcPriceDelta(i_takeProfit);

		if (type == ORDER_TYPE_BUY) {
			return price + delta;
		} else if (type == ORDER_TYPE_SELL) {
			return price - delta;
		}
		return -1;
	}

	double getSL(double price, ENUM_ORDER_TYPE type) {
		double delta = calcPriceDelta(i_stopLoss);

		if (type == ORDER_TYPE_BUY) {
			return price - delta;
		} else if (type == ORDER_TYPE_SELL) {
			return price + delta;
		}
		return -1;
	}

	bool openReversePosition(ulong ticket) {
		CPositionInfo pi;
		pi.SelectByTicket(ticket);

		ENUM_ORDER_TYPE type = getReverseOrderType(pi.PositionType());
		double volume = pi.Volume();
		double price = getMarketPrice(type);
		double tp = getTP(price, type);
		double sl = getSL(price, type);

		if (!m_trade.PositionOpen(m_symbol, type, volume, price, sl, tp, getReversePositionComment(ticket)) ||
			m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}

		PrintFormat(
			"Reverse position opened: volume=%f, price=%f, sl=%f, tp=%f",
			volume, price, sl, tp
		);

		uint size = m_positionsWithReverse.Size();
		ArrayResize(m_positionsWithReverse, size + 1, 1000);
		m_positionsWithReverse[size] = ticket;

/*
		if (i_closeStraightPosion) {
			if (!m_trade.PositionClose(ticket) || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
				return false;
			};
		}
*/
		return true;
	}
};
