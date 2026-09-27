use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::{Value, json};
use toml_edit::{Array, ArrayOfTables, DocumentMut, InlineTable, Item, Table, Value as TomlValue};

use crate::state::AppState;
use crate::util::api_error;

fn json_to_value(v: &Value) -> TomlValue {
    match v {
        Value::Null => TomlValue::from(""),
        Value::Bool(b) => TomlValue::from(*b),
        Value::Number(n) => match n.as_i64() {
            Some(i) => TomlValue::from(i),
            None => TomlValue::from(n.as_f64().unwrap_or(0.0)),
        },
        Value::String(s) => TomlValue::from(s.as_str()),
        Value::Array(a) => {
            let mut arr = Array::new();
            for e in a {
                arr.push(json_to_value(e));
            }
            TomlValue::Array(arr)
        }
        Value::Object(o) => {
            let mut t = InlineTable::new();
            for (k, val) in o {
                t.insert(k, json_to_value(val));
            }
            TomlValue::InlineTable(t)
        }
    }
}

fn json_to_item(v: &Value) -> Item {
    match v {
        Value::Object(o) => {
            let mut t = Table::new();
            for (k, val) in o {
                t.insert(k, json_to_item(val));
            }
            Item::Table(t)
        }
        Value::Array(a) if !a.is_empty() && a.iter().all(Value::is_object) => {
            let mut aot = ArrayOfTables::new();
            for e in a {
                if let Value::Object(o) = e {
                    let mut t = Table::new();
                    for (k, val) in o {
                        t.insert(k, json_to_item(val));
                    }
                    aot.push(t);
                }
            }
            Item::ArrayOfTables(aot)
        }
        _ => Item::Value(json_to_value(v)),
    }
}

fn sync_table(table: &mut Table, obj: &serde_json::Map<String, Value>) {
    let existing: Vec<String> = table.iter().map(|(k, _)| k.to_owned()).collect();
    for k in existing {
        if !obj.contains_key(&k) || obj[&k].is_null() {
            table.remove(&k);
        }
    }

    for (k, v) in obj {
        if v.is_null() {
            continue;
        }
        match (table.get_mut(k), v) {
            (Some(Item::Table(t)), Value::Object(o)) => sync_table(t, o),
            (Some(Item::Value(old)), _) if !v.is_object() => {
                let decor = old.decor().clone();
                *old = json_to_value(v);
                *old.decor_mut() = decor;
            }
            _ => {
                table.insert(k, json_to_item(v));
            }
        }
    }
}

pub async fn get_config(State(ctx): State<AppState>) -> Response {
    match std::fs::read_to_string(&ctx.cfg.config_path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            api_error(StatusCode::NOT_FOUND, "config.toml not found")
        }
        Err(e) => api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
        Ok(s) => match toml::from_str::<Value>(&s) {
            Ok(v) => Json(v).into_response(),
            Err(e) => api_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("invalid TOML in {}: {e}", ctx.cfg.config_path),
            ),
        },
    }
}

pub async fn put_config(State(ctx): State<AppState>, Json(body): Json<Value>) -> Response {
    let Value::Object(obj) = &body else {
        return api_error(StatusCode::BAD_REQUEST, "body must be a JSON object");
    };

    let mut doc = match std::fs::read_to_string(&ctx.cfg.config_path) {
        Ok(s) => match s.parse::<DocumentMut>() {
            Ok(d) => d,
            Err(e) => {
                return api_error(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("invalid TOML in {}: {e}", ctx.cfg.config_path),
                );
            }
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => DocumentMut::new(),
        Err(e) => return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };

    sync_table(doc.as_table_mut(), obj);

    let tmp = format!("{}.tmp", ctx.cfg.config_path);
    if let Err(e) = std::fs::write(&tmp, doc.to_string()) {
        return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
    }
    if let Err(e) = std::fs::rename(&tmp, &ctx.cfg.config_path) {
        return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
    }
    Json(json!({"status": "ok"})).into_response()
}
