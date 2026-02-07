//! Node type selection screen

use crate::app::App;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem},
    Frame,
};

pub fn draw(f: &mut Frame, app: &App, area: Rect) {
    // Split into two columns: herbs and ores
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(area);

    // Draw herbs list
    draw_node_list(
        f,
        &app.herbs,
        chunks[0],
        " Herbs (Tab to switch) ",
        app.active_node_list == 0,
        if app.active_node_list == 0 {
            app.node_list.selected
        } else {
            usize::MAX
        },
    );

    // Draw ores list
    draw_node_list(
        f,
        &app.ores,
        chunks[1],
        " Ores (Tab to switch) ",
        app.active_node_list == 1,
        if app.active_node_list == 1 {
            app.node_list.selected
        } else {
            usize::MAX
        },
    );
}

fn draw_node_list(
    f: &mut Frame,
    nodes: &[crate::app::NodeSelection],
    area: Rect,
    title: &str,
    is_active: bool,
    selected_idx: usize,
) {
    let items: Vec<ListItem> = nodes
        .iter()
        .enumerate()
        .map(|(i, node)| {
            let checkbox = if node.selected { "[x]" } else { "[ ]" };

            let style = if i == selected_idx {
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD)
            } else if node.selected {
                Style::default().fg(Color::Cyan)
            } else {
                Style::default().fg(Color::DarkGray)
            };

            let prefix = if i == selected_idx { "> " } else { "  " };

            ListItem::new(format!(
                "{}{} {} ({})",
                prefix, checkbox, node.name, node.count
            ))
            .style(style)
        })
        .collect();

    let border_color = if is_active {
        Color::Cyan
    } else {
        Color::DarkGray
    };

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(title)
            .border_style(Style::default().fg(border_color)),
    );

    f.render_widget(list, area);
}
