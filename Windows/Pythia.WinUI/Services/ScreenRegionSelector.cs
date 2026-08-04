using System.Drawing;
using System.Windows.Forms;

namespace Pythia.Services;

public static class ScreenRegionSelector
{
    public static Rectangle? Select()
    {
        using var selector = new SelectionForm();
        return selector.ShowDialog() == DialogResult.OK ? selector.SelectedRegion : null;
    }

    private sealed class SelectionForm : Form
    {
        private readonly Rectangle _virtualScreen;
        private Point _start;
        private Point _current;
        private bool _selecting;

        public SelectionForm()
        {
            _virtualScreen = SystemInformation.VirtualScreen;
            if (_virtualScreen.Width <= 0 || _virtualScreen.Height <= 0)
                throw new InvalidOperationException("无法读取虚拟桌面范围。");
            AutoScaleMode = AutoScaleMode.None;
            Bounds = _virtualScreen;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            TopMost = true;
            DoubleBuffered = true;
            KeyPreview = true;
            Cursor = Cursors.Cross;
            BackColor = Color.Black;
            Opacity = 0.34;
        }

        public Rectangle? SelectedRegion { get; private set; }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            Activate();
            Focus();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.Clear(Color.Black);
            var selection = NormalizeSelection(_start, _current);
            if (!_selecting && selection.Width == 0) return;
            if (selection.Width > 0 && selection.Height > 0)
            {
                using var border = new Pen(Color.FromArgb(255, 58, 160, 255), 2);
                e.Graphics.DrawRectangle(border, selection.X, selection.Y,
                    Math.Max(0, selection.Width - 1), Math.Max(0, selection.Height - 1));
                var label = $"{selection.Width} × {selection.Height}";
                var labelSize = e.Graphics.MeasureString(label, Font);
                var labelRect = new RectangleF(selection.X, Math.Max(0, selection.Y - labelSize.Height - 6),
                    labelSize.Width + 12, labelSize.Height + 4);
                using var labelBackground = new SolidBrush(Color.FromArgb(220, 24, 24, 24));
                e.Graphics.FillRectangle(labelBackground, labelRect);
                e.Graphics.DrawString(label, Font, Brushes.White, labelRect.X + 6, labelRect.Y + 2);
            }
            using var hintBackground = new SolidBrush(Color.FromArgb(215, 24, 24, 24));
            var hint = "拖动选择 OCR 区域 · Esc 或右键取消";
            var hintSize = e.Graphics.MeasureString(hint, Font);
            var hintRect = new RectangleF((ClientSize.Width - hintSize.Width) / 2 - 12, 20,
                hintSize.Width + 24, hintSize.Height + 10);
            e.Graphics.FillRectangle(hintBackground, hintRect);
            e.Graphics.DrawString(hint, Font, Brushes.White, hintRect.X + 12, hintRect.Y + 5);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Right)
            {
                DialogResult = DialogResult.Cancel;
                Close();
                return;
            }
            if (e.Button != MouseButtons.Left) return;
            _start = e.Location;
            _current = e.Location;
            _selecting = true;
            Capture = true;
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!_selecting) return;
            _current = new Point(
                Math.Clamp(e.X, 0, ClientSize.Width),
                Math.Clamp(e.Y, 0, ClientSize.Height));
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (!_selecting || e.Button != MouseButtons.Left) return;
            Capture = false;
            _selecting = false;
            _current = new Point(
                Math.Clamp(e.X, 0, ClientSize.Width),
                Math.Clamp(e.Y, 0, ClientSize.Height));
            var selection = NormalizeSelection(_start, _current);
            if (selection.Width < 5 || selection.Height < 5)
            {
                _start = Point.Empty;
                _current = Point.Empty;
                Invalidate();
                return;
            }
            SelectedRegion = new Rectangle(
                selection.X + _virtualScreen.Left,
                selection.Y + _virtualScreen.Top,
                selection.Width,
                selection.Height);
            DialogResult = DialogResult.OK;
            Close();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                DialogResult = DialogResult.Cancel;
                Close();
                return;
            }
            base.OnKeyDown(e);
        }

    }

    public static Rectangle NormalizeSelection(Point first, Point second) => new(
        Math.Min(first.X, second.X),
        Math.Min(first.Y, second.Y),
        Math.Abs(second.X - first.X),
        Math.Abs(second.Y - first.Y));
}
