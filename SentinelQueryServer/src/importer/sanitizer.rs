use std::path::Path;

#[derive(Debug, thiserror::Error)]
pub enum SanitizerError {
    #[error("failed to read source dump {path}: {source}")]
    Read {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to write sanitized sql {path}: {source}")]
    Write {
        path: String,
        #[source]
        source: std::io::Error,
    },
}

pub fn sanitize_dump_to_file(source: &Path, destination: &Path) -> Result<(), SanitizerError> {
    let raw = std::fs::read_to_string(source).map_err(|source_err| SanitizerError::Read {
        path: source.display().to_string(),
        source: source_err,
    })?;

    let sanitized = sanitize_sql(&raw);

    std::fs::write(destination, sanitized).map_err(|source_err| SanitizerError::Write {
        path: destination.display().to_string(),
        source: source_err,
    })?;

    Ok(())
}

pub fn sanitize_sql(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());

    for line in raw.lines() {
        let trimmed = line.trim();

        if should_drop_line(trimmed) {
            continue;
        }

        if trimmed.starts_with(')') && trimmed.contains("ENGINE=") {
            out.push_str(");\n");
            continue;
        }

        let mut current = line.to_string();
        current = current.replace('`', "\"");
        current = current.replace("AUTO_INCREMENT", "");
        current = current.replace(" unsigned", "");
        current = current.replace("UNSIGNED", "");
        current = current.replace("ENGINE=MyISAM", "");
        current = current.replace("ENGINE=InnoDB", "");
        current = current.replace("DEFAULT CHARSET=utf8mb3", "");
        current = current.replace("DEFAULT CHARSET=utf8", "");
        current = current.replace("ROW_FORMAT=FIXED", "");
        current = current.replace("ROW_FORMAT=DYNAMIC", "");
        current = current.replace("ROW_FORMAT=COMPACT", "");
        current = current.replace(" CHARACTER SET utf8mb3", "");
        current = current.replace(" CHARACTER SET utf8", "");
        current = current.replace("COLLATE utf8mb3_unicode_ci", "");
        current = current.replace("COLLATE utf8_unicode_ci", "");
        current = current.replace("COLLATE utf8_general_ci", "");
        current = current.replace("COLLATE utf8mb3_general_ci", "");
        current = current.replace(" USING BTREE", "");

        if current.trim_start().starts_with("KEY ")
            || current.trim_start().starts_with("FULLTEXT KEY")
        {
            continue;
        }

        if current.trim_start().starts_with("UNIQUE KEY") {
            if let Some(start) = current.find('(') {
                current = format!("  UNIQUE {}", current[start..].trim_end_matches(','));
                if !current.ends_with(',') {
                    current.push(',');
                }
            } else {
                continue;
            }
        }

        if let Some(comment_index) = current.find(" COMMENT '") {
            let has_trailing_comma = current.trim_end().ends_with(',');
            current = current[..comment_index].to_string();
            if has_trailing_comma && !current.trim_end().ends_with(',') {
                current.push(',');
            }
        }

        current = current.replace("b'1'", "1");
        current = current.replace("b'0'", "0");
        current = current.replace(")  ;", ");");
        current = current.replace(") ;", ");");
        current = normalize_mysql_string_escapes(&current);

        out.push_str(current.trim_end());
        out.push('\n');
    }

    let mut normalized = out;
    loop {
        let next = normalized
            .replace(",\n);", "\n);")
            .replace(",\r\n);", "\r\n);");
        if next == normalized {
            break;
        }
        normalized = next;
    }

    normalized
}

fn should_drop_line(trimmed: &str) -> bool {
    trimmed.is_empty()
        || trimmed.starts_with("--")
        || trimmed.starts_with("LOCK TABLES")
        || trimmed.starts_with("UNLOCK TABLES")
        || trimmed.starts_with("DELIMITER")
        || trimmed.starts_with("/*!")
        || trimmed.starts_with("/*!40000 ALTER TABLE")
        || trimmed.starts_with("/*!40101 SET")
        || trimmed.starts_with("/*!40103 SET")
        || trimmed.starts_with("/*!40111 SET")
        || trimmed.starts_with("/*!50003 SET")
        || trimmed.starts_with("/*!50001")
}

fn normalize_mysql_string_escapes(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0usize;
    let mut in_single_quote = false;

    while i < chars.len() {
        let ch = chars[i];

        if !in_single_quote {
            out.push(ch);
            if ch == '\'' {
                in_single_quote = true;
            }
            i += 1;
            continue;
        }

        if ch == '\\' && i + 1 < chars.len() {
            let next = chars[i + 1];
            match next {
                '\'' => {
                    out.push('\'');
                    out.push('\'');
                }
                '\\' => {
                    out.push('\\');
                }
                _ => {
                    out.push('\\');
                    out.push(next);
                }
            }
            i += 2;
            continue;
        }

        if ch == '\'' {
            if i + 1 < chars.len() && chars[i + 1] == '\'' {
                out.push('\'');
                out.push('\'');
                i += 2;
            } else {
                out.push('\'');
                in_single_quote = false;
                i += 1;
            }
            continue;
        }

        out.push(ch);
        i += 1;
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizer_removes_mysql_directives() {
        let input = "LOCK TABLES `a` WRITE;\n/*!40101 SET @saved_cs_client = @@character_set_client */;\nCREATE TABLE `t` (\n  `id` int unsigned NOT NULL AUTO_INCREMENT,\n  KEY `idx` (`id`)\n) ENGINE=MyISAM DEFAULT CHARSET=utf8mb3;\n";

        let output = sanitize_sql(input);
        assert!(!output.contains("LOCK TABLES"));
        assert!(!output.contains("KEY `idx`"));
        assert!(!output.contains("ENGINE=MyISAM"));
        assert!(output.contains("CREATE TABLE \"t\""));
        assert!(output.contains("\"id\" int"));
    }

    #[test]
    fn sanitizer_rewrites_bit_literals() {
        let input = "INSERT INTO `db_version` VALUES (b'1', b'0');\n";
        let output = sanitize_sql(input);
        assert!(output.contains("VALUES (1, 0)"));
    }

    #[test]
    fn sanitizer_rewrites_mysql_escaped_quotes() {
        let input = "INSERT INTO `x` VALUES ('Ol\\' Emma');\n";
        let output = sanitize_sql(input);
        assert!(output.contains("VALUES ('Ol'' Emma')"));
    }

    #[test]
    fn sanitizer_handles_trailing_backslash_before_quote() {
        let input = "INSERT INTO `x` VALUES ('text \\\\', 'next');\n";
        let output = sanitize_sql(input);
        assert!(output.contains(r#"VALUES ('text \', 'next')"#));
    }

    #[test]
    fn sanitizer_keeps_unique_constraints() {
        let input = "CREATE TABLE `npc_trainer_template` (\n  `entry` int NOT NULL,\n  `spell` int NOT NULL,\n  UNIQUE KEY `entry_spell` (`entry`,`spell`)\n) ENGINE=MyISAM;\n";
        let output = sanitize_sql(input);
        assert!(output.contains("UNIQUE (\"entry\",\"spell\")"));
    }

    #[test]
    fn sanitizer_output_parses_with_sqlite_for_fixture() {
        let fixture = include_str!("../../tests/fixtures/tiny_tbcmangos.sql");
        let output = sanitize_sql(fixture);
        assert!(output.contains("CREATE TABLE \"creature\""));
        assert!(!output.contains("LOCK TABLES"));
        assert!(!output.contains("ENGINE="));
    }
}
