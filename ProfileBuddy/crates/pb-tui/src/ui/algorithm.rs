//! Algorithm configuration screen

use crate::app::App;
use pb_core::{Algorithm, RandomStrategy};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

pub fn draw(f: &mut Frame, app: &App, area: Rect) {
    // Split into algorithm and randomization sections
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(7),  // Algorithm section
            Constraint::Length(7),  // Randomization section
            Constraint::Min(3),     // Help text
        ])
        .split(area);

    // Draw algorithm selection
    draw_algorithm_list(f, app, chunks[0]);

    // Draw randomization selection
    draw_randomization_list(f, app, chunks[1]);

    // Draw help text
    let help = Paragraph::new("Press Enter or G to generate route")
        .style(Style::default().fg(Color::DarkGray))
        .block(Block::default().borders(Borders::ALL).title(" Help "));

    f.render_widget(help, chunks[2]);
}

fn draw_algorithm_list(f: &mut Frame, app: &App, area: Rect) {
    let algorithms = [
        (Algorithm::Tsp, "TSP (Nearest Neighbor + 2-opt)", "Recommended - Fast and effective"),
        (Algorithm::Cluster, "Cluster + Connect", "Groups nearby nodes into hotspots"),
        (Algorithm::Density, "Density-Based", "Follows high-density areas"),
    ];

    let items: Vec<ListItem> = algorithms
        .iter()
        .enumerate()
        .map(|(i, (algo, name, desc))| {
            let is_selected = *algo == app.algorithm;
            let is_highlighted = i == app.algo_list.selected;

            let radio = if is_selected { "(o)" } else { "( )" };

            let style = if is_highlighted {
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD)
            } else if is_selected {
                Style::default().fg(Color::Cyan)
            } else {
                Style::default().fg(Color::White)
            };

            let prefix = if is_highlighted { "> " } else { "  " };

            ListItem::new(format!("{}{} {} - {}", prefix, radio, name, desc)).style(style)
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Optimization Algorithm ")
            .border_style(Style::default().fg(Color::Blue)),
    );

    f.render_widget(list, area);
}

fn draw_randomization_list(f: &mut Frame, app: &App, area: Rect) {
    let strategies = [
        (RandomStrategy::None, "None", "Deterministic route"),
        (RandomStrategy::RouteVariation, "Route Variation", "Randomize start point and direction"),
        (RandomStrategy::Both, "Route + Node Subset", "Maximum variation"),
    ];

    let items: Vec<ListItem> = strategies
        .iter()
        .enumerate()
        .map(|(i, (strat, name, desc))| {
            let is_selected = *strat == app.randomization;
            let is_highlighted = i + 3 == app.algo_list.selected;

            let radio = if is_selected { "(o)" } else { "( )" };

            let style = if is_highlighted {
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD)
            } else if is_selected {
                Style::default().fg(Color::Cyan)
            } else {
                Style::default().fg(Color::White)
            };

            let prefix = if is_highlighted { "> " } else { "  " };

            ListItem::new(format!("{}{} {} - {}", prefix, radio, name, desc)).style(style)
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Randomization Strategy ")
            .border_style(Style::default().fg(Color::Blue)),
    );

    f.render_widget(list, area);
}
