#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include "ExpertParams.mqh"

class CDayHLNG {
public:
	CDayHLNG::CDayHLNG() {
		m_highTicket = m_lowTicket = 0;
	};

	bool Init(const string symbol, const ulong magicNumber, const ExpertParams& params) {
		m_symbol = symbol;
		if (!m_symbolInfo.Name(m_symbol)) { return false; }

		m_magicNumber = magicNumber;
		m_trade.SetExpertMagicNumber(m_magicNumber);

		checkAndCopyParams(params);

		if (!EventSetTimer(60)) { return false; }

		m_currentBarTime = getLastRateTime();
		if (m_currentBarTime == 0) { return false; }

		return true;
	}

	void Deinit(const int reason) { EventKillTimer(); }

	void OnTick() {
		if (!checkOpenedPositions()) { return; }

		int positionsTotal = PositionsTotal();
		for (int i = positionsTotal - 1; i >= 0; i--) {
			if (checkPositionMagickNumber(i)) {
				if (m_breakevenTriggerLevel > 0 && checkReachBreakevenLevel()) {
					setBreakeven();
				}
				if (m_fixedTrailLevel > 0 && m_fixedTrail > 0) {
					trailPosition();
				}
			}
		}
	}

	void OnTimer() {
		datetime t = getLastRateTime();
		if (t == m_currentBarTime || !checkAllowTrade()) return;

		MqlRates rates[1];
		if (CopyRates(m_symbol, PERIOD_D1, 1, 1, rates) == -1) {
			PrintFormat("ERROR: CopyRates: %d", GetLastError());
			return;
		}

		if (checkRateLimits(rates[0]) && !openOrders(rates[0])) {
			deleteAllOrders();
			return;
		}
		m_currentBarTime = t;
	}

	void OnTrade() {}

	void OnTradeTransaction(const MqlTradeTransaction& transaction, const MqlTradeRequest& request, const MqlTradeResult& result) {
		if (request.action == TRADE_ACTION_REMOVE) {
			PrintFormat("OnTradeTransaction: ticket=%I64u, retcode=%I32u", request.order, result.retcode);
		}
	}

private:
	// Входные параметры
	string m_symbol;
	ulong m_magicNumber;
	ENUM_HIGH_ORDER_TYPE m_highOrderType;
	ENUM_LOW_ORDER_TYPE m_lowOrderType;
	uint m_highOffset;
	uint m_lowOffset;
	uint m_minLimit;
	uint m_maxLimit;
	double m_riskLimit;
	double m_fixedVolume;
	uint m_fixedTP;
	uint m_fixedSL;
	double m_profitToRiskRatio;
	uint m_breakevenTriggerLevel;
	uint m_breakevenValue;
	uint m_fixedTrailLevel;
	uint m_fixedTrail;
	uint m_maxOpenedPositions;

	CTrade m_trade;
	CSymbolInfo m_symbolInfo;
	COrderInfo m_orderInfo;
	CPositionInfo m_positionInfo;
	CAccountInfo m_accountInfo;

	datetime m_currentBarTime;
	ulong m_highTicket;
	ulong m_lowTicket;

	bool checkAndCopyParams(const ExpertParams& params) {
		m_highOrderType = params.highOrderType;
		m_lowOrderType = params.lowOrderType;
		m_highOffset = params.highOffset;
		m_lowOffset = params.lowOffset;
		m_minLimit = params.minLimit;
		m_maxLimit = params.maxLimit;
		m_riskLimit = params.riskLimit;
		m_fixedVolume = params.fixedVolume;
		m_fixedTP = params.fixedTP;
		m_fixedSL = params.fixedSL;
		m_profitToRiskRatio = params.profitToRiskRatio;
		m_breakevenTriggerLevel = params.breakevenTriggerLevel;
		m_breakevenValue = params.breakevenValue;
		m_fixedTrailLevel = params.fixedTrailLevel;
		m_fixedTrail = params.fixedTrail;
		m_maxOpenedPositions = params.maxOpenedPositions;
		return true;
	}

	datetime getLastRateTime() {
		datetime buf[1];
		if (CopyTime(m_symbol, PERIOD_D1, 0, 1, buf) == 1) { return buf[0]; }
		return 0;
	}

	bool checkAllowTrade() {
		return m_maxOpenedPositions == 0 || PositionsTotal() < m_maxOpenedPositions;
	}

	bool checkRateLimits(const MqlRates& rate) {
		uint delta = (int)MathFloor((rate.high - rate.low) / m_symbolInfo.Point());
		if (delta < m_minLimit) {
			PrintFormat("NOTICE: Bar is less than limit: bar=%d, limit=%d", delta, m_minLimit);
			return false;
		} else if (delta > m_maxLimit) {
			PrintFormat("NOTICE: Bar is greater than limit: bar=%d, limit=%d", delta, m_maxLimit);
			return false;
		}
		return true;
	}

	bool checkOpenedPositions() {
		return m_positionInfo.SelectByMagic(m_symbol, m_magicNumber);
	}

	bool checkPositionMagickNumber(int positionIndex) {
		return m_positionInfo.SelectByIndex(positionIndex) && m_positionInfo.Magic() == m_magicNumber;
	}

	void deleteAllOrders() {
		int ordersTotal = OrdersTotal();
		for (int i = ordersTotal - 1; i >=0; i--) {
			if (m_orderInfo.SelectByIndex(i) && m_orderInfo.Magic() == m_magicNumber) {
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
    	return adjustVolume(m_accountInfo.Balance() * m_riskLimit / MathAbs(loss));
	}

	double getDeltaSL(const MqlRates& rate) {
		return m_fixedSL > 0 ?
			m_fixedSL * m_symbolInfo.Point() :
			rate.high - rate.low + (m_highOffset + m_lowOffset) * m_symbolInfo.Point();
	}

	double getDeltaTP(double deltaSL) {
		return m_fixedTP > 0 ?
			m_fixedTP * m_symbolInfo.Point() :
			deltaSL * m_profitToRiskRatio;
	}

	double getHighSL(double price, double deltaSL) {
		return m_highOrderType == DAYHL_BUY_STOP ? price - deltaSL : price + deltaSL;
	}

	double getHighTP(double price, double deltaTP) {
		return m_highOrderType == DAYHL_BUY_STOP ? price + deltaTP : price - deltaTP;
	}

	bool openHighOrder(const MqlRates& rate, double deltaSL, double deltaTP) {
		double price = rate.high + m_highOffset * m_symbolInfo.Point();
		double sl = getHighSL(price, deltaSL);
		double volume = m_fixedVolume > 0 ?
			m_fixedVolume :
			calcVolume(price, sl, m_highOrderType == DAYHL_BUY_STOP ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
		if (volume < m_symbolInfo.LotsMin()) {
			PrintFormat("WARNING: High volume too small");
			return true;
		}
		double tp = getHighTP(price, deltaTP);
		bool success = m_highOrderType == DAYHL_BUY_STOP ?
			m_trade.BuyStop(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY) :
			m_trade.SellLimit(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY);
		if (!success || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}
		m_highTicket = m_trade.ResultOrder();
		return true;
	}

	double getLowSL(double price, double deltaSL) {
		return m_lowOrderType == DAYHL_SELL_STOP ? price + deltaSL : price - deltaSL;
	}

	double getLowTP(double price, double deltaTP) {
		return m_lowOrderType == DAYHL_SELL_STOP ? price - deltaTP : price + deltaTP;
	}

	bool openLowOrder(const MqlRates& rate, double deltaSL, double deltaTP) {
		double price = rate.low - m_lowOffset * m_symbolInfo.Point();
		double sl = getLowSL(price, deltaSL);
		double volume = m_fixedVolume > 0 ?
			m_fixedVolume :
			calcVolume(price, sl, m_lowOrderType == DAYHL_SELL_STOP ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
		if (volume < m_symbolInfo.LotsMin()) {
			PrintFormat("WARNING: Low volume too small");
			return true;
		}
		double tp = getLowTP(price, deltaTP);
		bool success = m_lowOrderType == DAYHL_SELL_STOP ?
			m_trade.SellStop(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY) :
			m_trade.BuyLimit(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY);
		if (!success || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}
		m_highTicket = m_trade.ResultOrder();
		return true;
	}

	bool checkBullBar(const MqlRates& rate) {
		return rate.open < rate.close;
	}

	bool openOrders(const MqlRates& rate) {
		double deltaSL = getDeltaSL(rate);
		double deltaTP = getDeltaTP(deltaSL);

		if (checkBullBar(rate)) {
			return openHighOrder(rate, deltaSL, deltaTP) && openLowOrder(rate, deltaSL, deltaTP);
		}
		return openLowOrder(rate, deltaSL, deltaTP) && openHighOrder(rate, deltaSL, deltaTP);
	}

	// Проверка достижения уровня установки безубыточности
	bool checkReachBreakevenLevel() {
		ENUM_POSITION_TYPE type = m_positionInfo.PositionType();
		double openPrice = m_positionInfo.PriceOpen(),
			   currentPrice = m_positionInfo.PriceCurrent(),
			   sl = m_positionInfo.StopLoss();
		double delta = m_breakevenTriggerLevel * m_symbolInfo.Point();
		return (type == POSITION_TYPE_BUY && sl < openPrice && currentPrice >= openPrice + delta) ||
			(type == POSITION_TYPE_SELL && sl > openPrice && currentPrice <= openPrice - delta);
	}

	void setBreakeven() {
		ulong ticket = m_positionInfo.Ticket();
		ENUM_POSITION_TYPE type = m_positionInfo.PositionType();
		double price = m_positionInfo.PriceOpen(),
			   tp = m_positionInfo.TakeProfit();

		double delta = m_breakevenValue * m_symbolInfo.Point();

		double sl = price + (type == POSITION_TYPE_BUY ? 1 : -1) * delta;

		if (m_trade.PositionModify(ticket, sl, tp)) {
			PrintFormat("Change SL: ticket=%I64u, SL=%f", ticket, sl);
		} else {
			PrintFormat("ERROR: Change SL failed: %d", GetLastError());
		}
	}

	void trailPosition() {
		ENUM_POSITION_TYPE type = m_positionInfo.PositionType();
		ulong ticket = m_positionInfo.Ticket();
		double openPrice = m_positionInfo.PriceOpen(),
			   currentPrice = m_positionInfo.PriceCurrent(),
			   tp = m_positionInfo.TakeProfit(),
			   sl = m_positionInfo.StopLoss();

		double trailLevelDelta = m_fixedTrailLevel * m_symbolInfo.Point();
		double trailDelta = m_fixedTrail * m_symbolInfo.Point();

		if (type == POSITION_TYPE_BUY && currentPrice - trailLevelDelta > openPrice && currentPrice - trailDelta > sl) {
//			PrintFormat("DEBUG: trailPosition: ticket=%I64u, openPrice=%f, currentPrice=%f, fixedDelta=%f", ticket, openPrice, currentPrice, trailDelta);
			m_trade.PositionModify(ticket, currentPrice - trailDelta, tp);
		} else if (type == POSITION_TYPE_SELL && currentPrice + trailLevelDelta < openPrice && currentPrice + trailDelta < sl) {
//			PrintFormat("DEBUG: trailPosition: ticket=%I64u, openPrice=%f, currentPrice=%f, fixedDelta=%f", ticket, openPrice, currentPrice, trailDelta);
			m_trade.PositionModify(ticket, currentPrice + trailDelta, tp);
		}
	}
/*
	void calcStartMoment();
	void calcStopMoment();
	void calcStartStopMoments();
	bool checkCanTrade(const MqlRates& rate);
	void startTrade();
	void setOrders(const MqlRates& rate);
	void stopTrade();
	void closeAllPositions();
	void deleteAllOrders();
	void setBreakEvenIfNeed();
	double adjustVolume(double volume);
	double calcVolume(double sellPrice, double buyPrice);
*/
//    void checkOpenedPositions(int positionsCount);
//    void checkClosedPositions(int positionsCount);
};

/*
double getPositionPricesDiff(const CPositionInfo& pi) {
	return pi.PositionType() == POSITION_TYPE_BUY ?
		pi.PriceCurrent() - pi.PriceOpen() :
		pi.PriceOpen() - pi.PriceCurrent();
	// PrintFormat("getPositionPricesDiff: type=%d, priceCurrent=%f, priceOpen=%f, priceDiff=%f",
	//     pi.PositionType(), pi.PriceCurrent(), pi.PriceOpen(), priceDiff);
	// return priceDiff;
}

void CDayHLNG::setBreakEvenIfNeed() {
	m_position.SelectByTicket(m_positionTicket);
	double price = m_position.PriceOpen(),
		   currentPrice = m_position.PriceCurrent(),
		   tp = m_position.TakeProfit(),
		   sl = m_position.StopLoss(),
		   slNew;
	if (m_position.PositionType() == POSITION_TYPE_BUY && sl < price && currentPrice >= price + m_breakeven * m_priceDiff) {
		slNew = price;
	} else if (m_position.PositionType() == POSITION_TYPE_SELL && sl > price && currentPrice <= price - m_breakeven * m_priceDiff) {
		slNew = price;
	} else {
		return;
	}
	if (m_trade.PositionModify(m_positionTicket, slNew, tp)) {
		PrintFormat("Change position SL: %f -> %f, id=%I64u", sl, slNew, m_positionTicket);
	} else {
		PrintFormat("ERROR: Change SL failed: %d", GetLastError());
	}
}

void CDayHLNG::OnTick() {
	if (m_positionTicket == 0) return;
	setBreakEvenIfNeed();
}

void CDayHLNG::OnTimer() {
	datetime now = TimeLocal();
	if (now >= m_startMoment) {
		startTrade();
	} else if (now >= m_stopMoment) {
		stopTrade();
		calcStopMoment();
	}
}

void CDayHLNG::OnTrade() {
	int positionsCount = PositionsTotal();
	if (positionsCount > 0) {
		if (m_positionTicket == 0) {
			if (!m_position.SelectByMagic(Symbol(), m_magicNumber)) return;
			m_positionTicket = m_position.Identifier();
			PrintFormat("Position opened: id=%I64u", m_positionTicket);
		} else {
			if (!m_position.SelectByMagic(Symbol(), m_magicNumber)) {
				PrintFormat("Position closed: id=%I64u", m_positionTicket);
				m_positionTicket = 0;
			} else {
				long positionTicket = m_position.Identifier();
				if (positionTicket == m_positionTicket) return;
				PrintFormat("Position closed: id=%I64u", m_positionTicket);
				m_positionTicket = positionTicket;
				PrintFormat("Position opened: id=%I64u", m_positionTicket);
			}
		}
	} else {
		if (m_positionTicket == 0) return;
		PrintFormat("Position closed: id=%I64u", m_positionTicket);
		m_positionTicket = 0;
	}
}

void CDayHLNG::OnTradeTransaction(const MqlTradeTransaction& transaction, const MqlTradeRequest& request, const MqlTradeResult& result) {
//    checkPositionCountChanged();
}

bool CDayHLNG::checkCanTrade(const MqlRates& rate) {
	if (!m_account.TradeAllowed()) {
		PrintFormat("CDayHLNG::checkCanTrade: Trade not allowed");
		return false;
	}
	if (!m_account.TradeExpert()) {
		PrintFormat("CDayHLNG::checkCanTrade: Expert trade not allowed");
		return false;
	}
	uint barSize = (uint)MathRound((rate.high - rate.low) / m_symbol.Point());
	if (barSize < m_barMinLimit) {
		PrintFormat("Bar size is too small: low=%f, high=%f, size=%u", rate.low, rate.high, barSize);
		return false;
	}
	if (barSize > m_barMaxLimit) {
		PrintFormat("Bar size is too large: low=%f, high=%f, size=%u", rate.low, rate.high, barSize);
		return false;
	}
	return true;
}

double CDayHLNG::adjustVolume(double volume) {
	return MathRound(volume / m_symbol.LotsMin()) * m_symbol.LotsMin();
}

double CDayHLNG::calcVolume(double sellPrice, double buyPrice) {
	double loss = m_account.OrderProfitCheck(m_symbol.Name(), ORDER_TYPE_BUY, 1, sellPrice, buyPrice);
	return this.adjustVolume(m_account.Balance() * m_riskLimit / loss);
}

void CDayHLNG::setOrders(const MqlRates& rate) {
	double stopsLevel = m_symbol.StopsLevel();
	double point = m_symbol.Point();
	double bodyTop = rate.open > rate.close ? rate.open : rate.close;
	double bodyBottom = rate.open < rate.close ? rate.open : rate.close;
	double buyPrice = m_buyPrice = bodyTop + m_offsetPoints * point;
	double minBuyPrice = m_symbol.Ask() + stopsLevel * point;
	if (buyPrice < minBuyPrice) {
		PrintFormat("CDayHLNG::setOrders: buyPrice correction: %f -> %f", buyPrice, minBuyPrice);
		buyPrice = m_buyPrice = minBuyPrice;
	}
	double sellPrice = m_sellPrice = bodyBottom - m_offsetPoints * point;
	double maxSellPrice = m_symbol.Bid() - stopsLevel * point;
	if (sellPrice > maxSellPrice) {
		PrintFormat("CDayHLNG::setOrders: sellPrice correction: %f -> %f", sellPrice, maxSellPrice);
		sellPrice = m_sellPrice = maxSellPrice;
	}
	double volume = m_fixedVolume > 0 ? m_fixedVolume : this.calcVolume(sellPrice, buyPrice);
	if (volume < m_symbol.LotsMin()) {
		PrintFormat("CDayHLNG::setOrders: volume is less than minimal: volume=%f, minimal=%f", volume, m_symbol.LotsMin());
		return;
	}
	double delta = m_priceDiff = m_buyPrice - m_sellPrice;
	double buyTP = buyPrice + delta * m_profitToRiskRatio,
		   sellTP = sellPrice - delta * m_profitToRiskRatio;
	m_trade.BuyStop(volume, buyPrice, m_symbol.Name(), sellPrice, buyTP, ORDER_TIME_SPECIFIED, m_stopMoment);
	m_trade.SellStop(volume, sellPrice, m_symbol.Name(), buyPrice, sellTP, ORDER_TIME_SPECIFIED, m_stopMoment);
	PrintFormat("CDayHLNG::setOrders: high=%f buy=%f low=%f sell=%f delta=%f", rate.high, buyPrice, rate.low, sellPrice, delta);
}

void CDayHLNG::startTrade() {
	m_symbol.Refresh();
	m_symbol.RefreshRates();
	MqlRates rates[2];
	int n = CopyRates(m_symbol.Name(), PERIOD_H4, 0, 2, rates);
	if (n != -1 && rates[1].time >= m_startMoment) {
		if (checkCanTrade(rates[0])) {
			setOrders(rates[0]);
			calcStartMoment();
		} else {
			calcStartStopMoments();
		}
	}
}

void CDayHLNG::deleteAllOrders() {
	int ordersCount = OrdersTotal();
	COrderInfo oi;
	for (int i = ordersCount - 1; i >=0; i--) {
		if (oi.SelectByIndex(i) && oi.Magic() == m_magicNumber) {
			m_trade.OrderDelete(oi.Ticket());
		}
	}
}

void CDayHLNG::stopTrade() {
	if (m_positionTicket) m_trade.PositionClose(m_positionTicket);
	deleteAllOrders();
}

void CDayHLNG::calcStartMoment() {
	MqlDateTime dt;
	datetime now = TimeLocal(dt);
	if (dt.day_of_week == 0) {
		m_startMoment = now + 3600 * (4 + 23 - dt.hour) + 60 * (59 - dt.min) + (60 - dt.sec);
	} else if (dt.day_of_week == 1 && dt.hour < 4) {
		m_startMoment = now + 3600 * (3 - dt.hour) + 60 * (59 - dt.min) + (60 - dt.sec);
	} else {
		m_startMoment = now + 3600 * (24 * (7 - dt.day_of_week) + 4 + 23 - dt.hour) + 60 * (59 - dt.min) + (60 - dt.sec);
	}
	PrintFormat("now=%I64u, nextStartMoment=%I64u", now, m_startMoment);
}

void CDayHLNG::calcStopMoment() {
	m_stopMoment = m_startMoment + 414000;
}

void CDayHLNG::calcStartStopMoments() {
	calcStartMoment();
	calcStopMoment();
}

*/
