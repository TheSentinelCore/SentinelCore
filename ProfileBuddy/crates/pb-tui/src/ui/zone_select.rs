//! Zone selection screen

use crate::app::App;
use ratatui::{
    layout::Rect,
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem},
    Frame,
};

pub fn draw(f: &mut Frame, app: &App, area: Rect) {
    let items: Vec<ListItem> = app
        .zones
        .iter()
        .enumerate()
        .map(|(i, (_, name, count))| {
            let style = if i == app.zone_list.selected {
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };

            let prefix = if i == app.zone_list.selected {
                "> "
            } else {
                "  "
            };

            ListItem::new(format!("{}{} ({} nodes)", prefix, name, count)).style(style)
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(format!(" Select Zone ({} available) ", app.zones.len()))
            .border_style(Style::default().fg(Color::Blue)),
    );

    f.render_widget(list, area);
}
