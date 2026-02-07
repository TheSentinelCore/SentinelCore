//! UI rendering for ProfileBuddy

mod zone_select;
mod node_select;
mod algorithm;
mod preview;

use crate::app::{App, Screen};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

/// Main draw function
pub fn draw(f: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints([
            Constraint::Length(3), // Header
            Constraint::Min(10),   // Main content
            Constraint::Length(3), // Status bar
        ])
        .split(f.area());

    // Draw header
    draw_header(f, app, chunks[0]);

    // Draw main content based on screen
    match app.screen {
        Screen::GameVersion => draw_game_version(f, app, chunks[1]),
        Screen::ZoneSelect => zone_select::draw(f, app, chunks[1]),
        Screen::NodeSelect => node_select::draw(f, app, chunks[1]),
        Screen::AlgorithmConfig => algorithm::draw(f, app, chunks[1]),
        Screen::Preview => preview::draw(f, app, chunks[1]),
        Screen::Complete => draw_complete(f, app, chunks[1]),
    }

    // Draw status bar
    draw_status(f, app, chunks[2]);
}

fn draw_header(f: &mut Frame, app: &App, area: Rect) {
    let title = format!(
        " ProfileBuddy v{} - {} ",
        env!("CARGO_PKG_VERSION"),
        app.game_version.as_str()
    );

    let header = Paragraph::new(title)
        .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan)),
        );

    f.render_widget(header, area);
}

fn draw_status(f: &mut Frame, app: &App, area: Rect) {
    let status = Paragraph::new(app.status.as_str())
        .style(Style::default().fg(Color::Yellow))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Status ")
                .border_style(Style::default().fg(Color::DarkGray)),
        );

    f.render_widget(status, area);
}

fn draw_game_version(f: &mut Frame, app: &App, area: Rect) {
    let items: Vec<ListItem> = [pb_core::GameVersion::Era, pb_core::GameVersion::Tbc]
        .iter()
        .map(|v| {
            let style = if *v == app.game_version {
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };

            let prefix = if *v == app.game_version {
                "> "
            } else {
                "  "
            };

            ListItem::new(format!("{}{}", prefix, v.as_str())).style(style)
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Select Game Version ")
            .border_style(Style::default().fg(Color::Blue)),
    );

    f.render_widget(list, area);
}

fn draw_complete(f: &mut Frame, app: &App, area: Rect) {
    let text = if let Some(path) = &app.output_path {
        vec![
            Line::from(vec![
                Span::styled("Profile saved successfully!", Style::default().fg(Color::Green)),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::raw("Output: "),
                Span::styled(
                    path.display().to_string(),
                    Style::default().fg(Color::Cyan),
                ),
            ]),
            Line::from(""),
            if let Some(profile) = &app.profile {
                Line::from(vec![
                    Span::raw("Waypoints: "),
                    Span::styled(
                        profile.waypoints.len().to_string(),
                        Style::default().fg(Color::Yellow),
                    ),
                ])
            } else {
                Line::from("")
            },
            Line::from(""),
            Line::from(vec![
                Span::styled("Press Enter to create another profile", Style::default().fg(Color::DarkGray)),
            ]),
        ]
    } else {
        vec![Line::from("Error saving profile")]
    };

    let paragraph = Paragraph::new(text).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Complete ")
            .border_style(Style::default().fg(Color::Green)),
    );

    f.render_widget(paragraph, area);
}

/// Helper to create a centered rect
pub fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}
