//! Route preview screen

use crate::app::App;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

pub fn draw(f: &mut Frame, app: &App, area: Rect) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(60), Constraint::Percentage(40)])
        .split(area);

    // Draw route info
    draw_route_info(f, app, chunks[0]);

    // Draw ASCII map preview
    draw_ascii_map(f, app, chunks[1]);
}

fn draw_route_info(f: &mut Frame, app: &App, area: Rect) {
    let route = match &app.route {
        Some(r) => r,
        None => {
            let paragraph = Paragraph::new("No route generated")
                .block(Block::default().borders(Borders::ALL).title(" Route Info "));
            f.render_widget(paragraph, area);
            return;
        }
    };

    let items: Vec<ListItem> = vec![
        ListItem::new(Line::from(vec![
            Span::raw("Algorithm: "),
            Span::styled(
                route.algorithm.as_str(),
                Style::default().fg(Color::Cyan),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::raw("Waypoints: "),
            Span::styled(
                route.waypoints.len().to_string(),
                Style::default().fg(Color::Yellow),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::raw("Hotspots: "),
            Span::styled(
                route.hotspots.len().to_string(),
                Style::default().fg(Color::Magenta),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::raw("Distance: "),
            Span::styled(
                format!("{:.0} yards", route.total_distance),
                Style::default().fg(Color::Green),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::raw("Randomized: "),
            Span::styled(
                if route.randomized { "Yes" } else { "No" },
                Style::default().fg(if route.randomized {
                    Color::Green
                } else {
                    Color::DarkGray
                }),
            ),
        ])),
        ListItem::new(""),
        ListItem::new(Line::from(vec![
            Span::styled(
                "Press Enter to save, R to regenerate",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
    ];

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Route Info ")
            .border_style(Style::default().fg(Color::Blue)),
    );

    f.render_widget(list, area);
}

fn draw_ascii_map(f: &mut Frame, app: &App, area: Rect) {
    let route = match &app.route {
        Some(r) => r,
        None => {
            let paragraph = Paragraph::new("No route")
                .block(Block::default().borders(Borders::ALL).title(" Map Preview "));
            f.render_widget(paragraph, area);
            return;
        }
    };

    if route.waypoints.is_empty() {
        let paragraph = Paragraph::new("Empty route")
            .block(Block::default().borders(Borders::ALL).title(" Map Preview "));
        f.render_widget(paragraph, area);
        return;
    }

    // Find bounds
    let min_x = route
        .waypoints
        .iter()
        .map(|w| w.x)
        .fold(f32::MAX, f32::min);
    let max_x = route
        .waypoints
        .iter()
        .map(|w| w.x)
        .fold(f32::MIN, f32::max);
    let min_y = route
        .waypoints
        .iter()
        .map(|w| w.y)
        .fold(f32::MAX, f32::min);
    let max_y = route
        .waypoints
        .iter()
        .map(|w| w.y)
        .fold(f32::MIN, f32::max);

    // Create ASCII grid
    let width = (area.width as usize).saturating_sub(4).max(10);
    let height = (area.height as usize).saturating_sub(4).max(5);

    let mut grid = vec![vec![' '; width]; height];

    // Plot waypoints
    for (i, wp) in route.waypoints.iter().enumerate() {
        let x_range = max_x - min_x;
        let y_range = max_y - min_y;

        let grid_x = if x_range > 0.0 {
            ((wp.x - min_x) / x_range * (width - 1) as f32) as usize
        } else {
            width / 2
        };

        let grid_y = if y_range > 0.0 {
            ((wp.y - min_y) / y_range * (height - 1) as f32) as usize
        } else {
            height / 2
        };

        let grid_x = grid_x.min(width - 1);
        let grid_y = grid_y.min(height - 1);

        // Mark waypoint (use number for first 9, then *)
        let marker = if i < 9 {
            char::from_digit((i + 1) as u32, 10).unwrap_or('*')
        } else {
            '*'
        };

        // Check if it's a hotspot
        let is_hotspot = matches!(
            wp.waypoint_type,
            pb_core::optimizer::WaypointType::Hotspot { .. }
        );

        grid[grid_y][grid_x] = if is_hotspot { 'H' } else { marker };
    }

    // Convert grid to lines
    let lines: Vec<Line> = grid
        .iter()
        .map(|row| {
            let s: String = row.iter().collect();
            Line::from(s)
        })
        .collect();

    let paragraph = Paragraph::new(lines)
        .style(Style::default().fg(Color::Cyan))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Map Preview ")
                .border_style(Style::default().fg(Color::Blue)),
        );

    f.render_widget(paragraph, area);
}
