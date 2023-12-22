#include <Controls/Dialog.mqh>
#include <Controls/Label.mqh>
#include <Controls/WndContainer.mqh>
#include "StatData.mqh"

#define PANEL_WIDTH 200
#define PANEL_HEIGHT 200

class CInfoPanel: public CWndContainer {
public:
    virtual bool Create(const int x, const int y) {
        if (!CWndContainer::Create(0, "InfoPanel", 0, x, y, x + 190, y + 220)) {
            PrintFormat("ERROR: CWndContainer::Create failed: %d", GetLastError());
            return false;
        }

        int baseX = 10, baseY = 5;
        m_symbolCountersTitle = CreateLabel("По инструменту", "SymbolCountersTitle", baseX, baseY);
        m_symbolCountersTitle.FontSize(m_symbolCountersTitle.FontSize() + 2);
        m_symbolDirectStaticLabel = CreateLabel("Прямых:", "SymbolDirectStaticLabel", baseX, baseY + 22);
        m_symbolDirectValueLabel = CreateLabel("0", "SymbolDirectValueLabel", baseX + 80, baseY + 22);
        m_symbolReverseStaticLabel = CreateLabel("Реверсных:", "SymbolReverseStaticLabel", baseX, baseY + 42);
        m_symbolReverseValueLabel = CreateLabel("0", "SymbolReverseValueLabel", baseX + 80, baseY + 42);
        m_symbolInverseStaticLabel = CreateLabel("Инверсных:", "SymbolInverseStaticLabel", baseX, baseY + 62);
        m_symbolInverseValueLabel = CreateLabel("0", "SymbolInverseValueLabel", baseX + 80, baseY + 62);
        m_symbolSummaryStaticLabel = CreateLabel("Всего:", "SymbolSummaryStaticLabel", baseX, baseY + 82);
        m_symbolSummaryValueLabel = CreateLabel("0", "SymbolSummaryValueLabel", baseX + 80, baseY + 82);

        baseY = 120;
        m_totalCountersTitle = CreateLabel("По портфелю", "TotalCountersTitle", baseX, baseY);
        m_totalCountersTitle.FontSize(m_totalCountersTitle.FontSize() + 2);
        m_totalDirectStaticLabel = CreateLabel("Прямых:", "TotalDirectStaticLabel", baseX, baseY + 22);
        m_totalDirectValueLabel = CreateLabel("0", "TotalDirectValueLabel", baseX + 80, baseY + 22);
        m_totalReverseStaticLabel = CreateLabel("Реверсных:", "TotalReverseStaticLabel", baseX, baseY + 42);
        m_totalReverseValueLabel = CreateLabel("0", "TotalReverseValueLabel", baseX + 80, baseY + 42);
        m_totalInverseStaticLabel = CreateLabel("Инверсных:", "TotalInverseStaticLabel", baseX, baseY + 62);
        m_totalInverseValueLabel = CreateLabel("0", "TotalInverseValueLabel", baseX + 80, baseY + 62);
        m_totalSummaryStaticLabel = CreateLabel("Всего:", "TotalSummaryStaticLabel", baseX, baseY + 82);
        m_totalSummaryValueLabel = CreateLabel("0", "TotalSummaryValueLabel", baseX + 80, baseY + 82);

        return true;
    }

    void SetInfo(const CStatData& data) {
        m_data = data;
        SetLabels();
    }

private:
    CLabel* m_symbolCountersTitle;
    CLabel* m_symbolDirectStaticLabel;
    CLabel* m_symbolDirectValueLabel;
    CLabel* m_symbolReverseStaticLabel;
    CLabel* m_symbolReverseValueLabel;
    CLabel* m_symbolInverseStaticLabel;
    CLabel* m_symbolInverseValueLabel;
    CLabel* m_symbolSummaryStaticLabel;
    CLabel* m_symbolSummaryValueLabel;
    CLabel* m_totalCountersTitle;
    CLabel* m_totalDirectStaticLabel;
    CLabel* m_totalDirectValueLabel;
    CLabel* m_totalReverseStaticLabel;
    CLabel* m_totalReverseValueLabel;
    CLabel* m_totalInverseStaticLabel;
    CLabel* m_totalInverseValueLabel;
    CLabel* m_totalSummaryStaticLabel;
    CLabel* m_totalSummaryValueLabel;

    CStatData m_data;

    virtual bool  Create(
        const long    chart,      // идентификатор графика
        const string  name,       // имя
        const int     subwin,     // подокно графика
        const int     x1,         // координата x1
        const int     y1,         // координата y1
        const int     x2,         // координата x2
        const int     y2          // координата y2
    ) {
        return CWndContainer::Create(chart, name, subwin, x1, y1, x2, y2);
    }

    void SetLabels() {
        m_symbolDirectValueLabel.Text(StringFormat("%d", m_data.symbolCounters.direct));
        m_symbolReverseValueLabel.Text(StringFormat("%d", m_data.symbolCounters.reverse));
        m_symbolInverseValueLabel.Text(StringFormat("%d", m_data.symbolCounters.inverse));
        int summary = m_data.symbolCounters.direct + m_data.symbolCounters.reverse + m_data.symbolCounters.inverse;
        m_symbolSummaryValueLabel.Text(StringFormat("%d", summary));
        m_totalDirectValueLabel.Text(StringFormat("%d", m_data.totalCounters.direct));
        m_totalReverseValueLabel.Text(StringFormat("%d", m_data.totalCounters.reverse));
        m_totalInverseValueLabel.Text(StringFormat("%d", m_data.totalCounters.inverse));
        summary = m_data.totalCounters.direct + m_data.totalCounters.reverse + m_data.totalCounters.inverse;
        m_totalSummaryValueLabel.Text(StringFormat("%d", summary));
    }

    CLabel* CreateLabel(string text, string name, int x, int y) {
        CLabel* label = new CLabel();
        if (!label) return NULL;

        if (!label.Create(0, name, 0, x, y, x + 50, y + 15)) {
            delete label;
            return NULL;
        }
        if (!label.Text(text)) {
            delete label;
            return NULL;
        }
        if (!Add(label)) {
            delete label;
            return NULL;
        }
        return label;
    }
};

class CInfoDialog: public CAppDialog {
private:
    CInfoPanel m_infoPanel;

    virtual bool Create(
        const long      chart,      // идентификатор графика
        const string    name,       // имя
        const int       subwin,     // подокно графика
        const int       x1,         // координата
        const int       y1,         // координата
        const int       x2,         // координата
        const int       y2          // координата
    ) { return CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2); }

public:
    virtual bool Create() {
        if (!CAppDialog::Create(0, "Информация о позициях", 0, 10, 10, 210, 280)) {
            return false;
        }

        if (!m_infoPanel.Create(0, 0)) {
            return false;
        }

        Add(m_infoPanel);

        return true;
    }

    virtual void OnClickButtonClose() {}

    virtual bool OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
        m_infoPanel.OnEvent(id, lparam, dparam, sparam);
        return CAppDialog::OnEvent(id, lparam, dparam, sparam);
    }

    void SetInfo(const CStatData& data) {
        m_infoPanel.SetInfo(data);
    }
};

//EVENT_MAP_BEGIN(CInfoDialog)
//EVENT_MAP_END(CAppDialog)
