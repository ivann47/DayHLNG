#include <Controls/Dialog.mqh>
#include <Controls/Label.mqh>
#include <Controls/WndContainer.mqh>
#include "StatData.mqh"

#define PANEL_X_POSITION    60
#define PANEL_Y_POSITION    15
#define PANEL_WIDTH 180
#define PANEL_HEIGHT 270
#define STATIC_LABEL_X_OFFSET   10
#define VALUE_LABEL_X_OFFSET    120
#define TITLE_HEIGHT    22
#define LABELS_HEIGHT   20
#define LABEL_WIDTH     50
#define LABEL_HEIGHT    15

class CInfoPanel: public CAppDialog {
public:
    virtual bool Create() {
        if (!CAppDialog::Create(0, "  О позициях", 0, PANEL_X_POSITION, PANEL_Y_POSITION, PANEL_X_POSITION + PANEL_WIDTH, PANEL_Y_POSITION + PANEL_HEIGHT)) {
            return false;
        }

        int baseY = 5;

        CreateTitle("По инструменту", "SymbolCountersTitle", baseY);
        m_symbolDirectValueLabel = CreateStaticAndValueLabels("Прямых:", "SymbolDirect", baseY += 22);
        m_symbolReverseValueLabel = CreateStaticAndValueLabels("Реверсных:", "SymbolReverse", baseY += 20);
        m_symbolInverseValueLabel = CreateStaticAndValueLabels("Инверсных:", "SymbolInverse", baseY += 20);
        m_symbolSummaryValueLabel = CreateStaticAndValueLabels("Всего:", "SymbolSummary", baseY += 20);

        CreateTitle("По портфелю", "TotalCountersTitle", baseY += 40);
        m_totalDirectValueLabel = CreateStaticAndValueLabels("Прямых:", "TotalDirect", baseY += 22);
        m_totalReverseValueLabel = CreateStaticAndValueLabels("Реверсных:", "TotalReverse", baseY += 20);
        m_totalInverseValueLabel = CreateStaticAndValueLabels("Инверсных:", "TotalInverse", baseY += 20);
        m_totalSummaryValueLabel = CreateStaticAndValueLabels("Всего:", "TotalSummary", baseY += 20);

        return true;
    }

    virtual void OnClickButtonClose() {}

    virtual bool OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
        return CAppDialog::OnEvent(id, lparam, dparam, sparam);
    }

    void SetInfo(const CStatData& data) {
        m_data = data;
        SetLabels();
    }

private:
    CLabel* m_symbolDirectValueLabel;
    CLabel* m_symbolReverseValueLabel;
    CLabel* m_symbolInverseValueLabel;
    CLabel* m_symbolSummaryValueLabel;
    CLabel* m_totalDirectValueLabel;
    CLabel* m_totalReverseValueLabel;
    CLabel* m_totalInverseValueLabel;
    CLabel* m_totalSummaryValueLabel;

    CStatData m_data;

    virtual bool Create(
        const long      chart,      // идентификатор графика
        const string    name,       // имя
        const int       subwin,     // подокно графика
        const int       x1,         // координата
        const int       y1,         // координата
        const int       x2,         // координата
        const int       y2          // координата
    ) { return CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2); }

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

        if (!label.Create(0, name, 0, x, y, x + LABEL_WIDTH, y + LABEL_HEIGHT) ||
            !label.Text(text) ||
            !label.Font("Arial") ||
            !Add(label)
        ) {
            delete label;
            return NULL;
        }

        return label;
    }

    CLabel* CreateStaticLabel(string text, string name, int y) {
        return CreateLabel(text, name, STATIC_LABEL_X_OFFSET, y);
    }

    CLabel* CreateValueLabel(string text, string name, int y) {
        return CreateLabel(text, name, VALUE_LABEL_X_OFFSET, y);
    }

    void CreateTitle(string text, string name, int y) {
        CLabel* title = CreateStaticLabel(text, name, y);
        title.FontSize(11);
    }

    CLabel* CreateStaticAndValueLabels(string text, string prefix, int y) {
        CLabel* staticLabel = CreateStaticLabel(text, StringFormat("%sStaticLabel", prefix), y);
        CLabel* valueLabel = CreateValueLabel("0", StringFormat("%sValueLabel", prefix), y);
        staticLabel.FontSize(10);
        valueLabel.FontSize(10);
        return valueLabel;
    }
};

//EVENT_MAP_BEGIN(CInfoDialog)
//EVENT_MAP_END(CAppDialog)
