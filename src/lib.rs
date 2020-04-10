mod utils;

extern crate vecmath;
use itertools::Itertools;
use itertools::FoldWhile::{Continue, Done};
extern crate serde_json;
extern crate console_error_panic_hook;
use wasm_bindgen::prelude::*;
extern crate web_sys;

#[macro_use]
extern crate serde_derive;

// When the `wee_alloc` feature is enabled, use `wee_alloc` as the global
// allocator.
#[cfg(feature = "wee_alloc")]
#[global_allocator]
static ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

pub type Vector2 = vecmath::Vector2<f64>;

#[derive(Serialize, Deserialize, Debug, Clone)]
struct Field {
  source: Charge,
  density: usize,
  steps: usize,
  delta: f64,
  #[serde(skip_deserializing)]
  lines: Vec<Line>,
}

type Line = Vec<Point>;

type Point = Vector2;

#[derive(Serialize, Deserialize, Debug, Clone)]
struct Position {
    x: f64,
    y: f64,
}

#[derive(Serialize, Deserialize, Debug, Copy, Clone)]
enum Sign {
  Positive,
  Negative
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct Charge {
  id : usize,
  sign: Sign,
  magnitude: f64,
  position: Position,
  r: f64,
}

#[wasm_bindgen]
pub fn calculate_fields( width: f64, height: f64, fields_in_json: &JsValue ) -> JsValue {
  let fields: Vec<Field> = match fields_in_json.into_serde() {
    Ok(fields) => fields,
    Err(err) => { web_sys::console::log_1(&format!("{:#?}", err).into()); vec![] },
  };
  let new_fields = fields.iter().map(|field| {
    let source_position = [field.source.position.x, field.source.position.y];
    let delta_angle = 2.0 * std::f64::consts::PI / (field.density as f64);
    let lines =
      (0..field.density - 1).map(|index| {
        let angle = delta_angle * (index as f64);
        let dx = field.source.r * angle.cos();
        let dy = field.source.r * angle.sin();
        let start = vecmath::vec2_add([dx, dy], source_position);
        calculate_field_line(
          &fields.iter().map(|field| field.source.clone()).collect::<Vec<Charge>>(),
          field.steps, field.delta, field.source.sign, start, width, height
        )
      }).collect::<Vec<Line>>();
    Field {
      lines,
      ..field.clone()
    }
  }).collect::<Vec<Field>>();
  // web_sys::console::log_1(&format!("{:#?}", new_fields).into());
  JsValue::from_serde(&new_fields).unwrap()
}

fn calculate_field_line(charges: &Vec<Charge>, steps: usize, delta: f64, source_sign: Sign, start: Point, x_bound: f64, y_bound: f64) -> Line {
  (0..steps - 1).fold_while(vec![ start ], |mut line: Line, _| {
    let [x, y] = match line {
      _ if line.len() > 0 =>
        line[line.len()-1],
      _ =>
        [0.0, 0.0] // impossible
    };
    let previous_position: Vector2 = [x, y];
    let tolerance = 100.0;
    let out_of_bounds = x > x_bound + tolerance || x < -tolerance || y > y_bound + tolerance || y < -tolerance;
    if out_of_bounds {
      Done(line)
    } else {
      let net_field =
        charges.iter().fold([0.0, 0.0], |sum, charge| {
          let charge_position = [charge.position.x, charge.position.y];
          let d = distance(previous_position, charge_position) / 100.0;
          let magnitude = charge.magnitude / d.powf(2.0);
          let sign =
            match charge.sign {
              Sign::Positive => 1.0,
              Sign::Negative => -1.0
            };
          let field =
            vecmath::vec2_scale(
              vecmath::vec2_normalized(
                vecmath::vec2_sub(previous_position, charge_position)
            ), sign * magnitude);
          vecmath::vec2_add(sum, field)
        });
      let delta_vector =
        vecmath::vec2_scale(
          vecmath::vec2_normalized(net_field),
          delta
        );
      let next =
        vecmath::vec2_add(
          previous_position,
          match source_sign {
            Sign::Positive =>
              delta_vector,
            Sign::Negative =>
              vecmath::vec2_neg(delta_vector),
          }
        );
      line.push(next);
      Continue(line)
    }
  }).into_inner()
}

fn distance(a: Vector2, b: Vector2) -> f64 {
  ((b[0] - a[0]).powf(2.0) + (b[1] - a[1]).powf(2.0)).sqrt()
}