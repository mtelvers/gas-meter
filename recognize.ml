(*
 * Gas Meter Digit Recognition using Direct Pixel Comparison
 *
 * 1. Find the top-left corner of the digit (first bright pixel at 85% threshold)
 * 2. Extract a fixed 90x140 block of normalized grayscale pixels
 * 3. Compare using cosine similarity on the pixel vectors
 *)

(* Template dimensions *)
let template_width = 90
let template_height = 140

(* Offset to compensate for high threshold detecting inner bright region *)
let origin_offset = 10

type template = {
  digit: string;
  pixels: float array;
}

type recognition = {
  recognized_digit: string;
  confidence: float;
}

let rgb_to_gray { Color.r; g; b } =
  (r * 299 + g * 587 + b * 114) / 1000

let rgba_to_gray { Color.color; _ } = rgb_to_gray color

let get_gray img x y =
  match img with
  | Images.Rgb24 bmp -> rgb_to_gray (Rgb24.get bmp x y)
  | Images.Rgba32 bmp -> rgba_to_gray (Rgba32.get bmp x y)
  | Images.Index8 bmp ->
      Index8.get bmp x y
      |> Array.get bmp.Index8.colormap.Color.map
      |> rgb_to_gray
  | _ -> failwith "Unsupported image type"

let image_size = Images.size

let image_to_array img =
  let width, height = image_size img in
  Array.init height (fun y ->
    Array.init width (fun x -> get_gray img x y))

let image_stats_from_array arr =
  Array.fold_left (fun acc row ->
    Array.fold_left (fun (min_v, max_v) v ->
      (min min_v v, max max_v v)
    ) acc row
  ) (255, 0) arr

let find_digit_origin arr min_v max_v threshold =
  let high_threshold = min_v + (max_v - min_v) * 85 / 100 in
  let actual_threshold = max threshold high_threshold in
  let first_row =
    Array.find_index (fun row -> Array.exists (fun v -> v > actual_threshold) row) arr
    |> Option.value ~default:0
  in
  let first_col =
    Array.find_mapi (fun x _ ->
      Array.find_opt (fun row -> row.(x) > actual_threshold) arr
      |> Option.map (fun _ -> x)
    ) arr.(0) |> Option.value ~default:0
  in
  (max 0 (first_col - origin_offset), max 0 (first_row - origin_offset))

let extract_pixel_block arr min_v max_v x0 y0 =
  let height = Array.length arr in
  let width = Array.length arr.(0) in
  let range = float_of_int (max 1 (max_v - min_v)) in
  Array.init (template_width * template_height) (fun i ->
    let x = x0 + (i mod template_width) in
    let y = y0 + (i / template_width) in
    if x >= width || y >= height then 0.0
    else float_of_int (arr.(y).(x) - min_v) /. range)

let dot_product v1 v2 =
  Array.map2 ( *. ) v1 v2 |> Array.fold_left ( +. ) 0.0

let magnitude v =
  Array.fold_left (fun acc x -> acc +. x *. x) 0.0 v |> sqrt

let cosine_similarity v1 v2 =
  dot_product v1 v2 /. (magnitude v1 *. magnitude v2)

let create_template digit_name img =
  let arr = image_to_array img in
  let min_v, max_v = image_stats_from_array arr in
  let threshold = (min_v + max_v) / 2 in
  let x0, y0 = find_digit_origin arr min_v max_v threshold in
  { digit = digit_name; pixels = extract_pixel_block arr min_v max_v x0 y0 }

let create_template_from_file digit_name filename =
  Png.load filename [] |> create_template digit_name

let recognize_digit img templates =
  let arr = image_to_array img in
  let min_v, max_v = image_stats_from_array arr in
  let threshold = (min_v + max_v) / 2 in
  let x0, y0 = find_digit_origin arr min_v max_v threshold in
  let pixels = extract_pixel_block arr min_v max_v x0 y0 in
  templates
  |> List.map (fun tmpl -> (tmpl.digit, cosine_similarity pixels tmpl.pixels))
  |> List.fold_left
      (fun (best_d, best_s) (d, s) -> if s > best_s then (d, s) else (best_d, best_s))
      ("?", -1.0)
  |> fun (digit, confidence) -> { recognized_digit = digit; confidence }

let try_load_template template_dir digit =
  let filename = Printf.sprintf "%s/%s.png" template_dir digit in
  if Sys.file_exists filename then (
    Printf.eprintf "  Loaded template %s\n%!" digit;
    Some (create_template_from_file digit filename)
  ) else (
    Printf.eprintf "  Warning: Template %s not found\n%!" filename;
    None
  )

let load_templates template_dir =
  List.init 10 string_of_int
  |> List.filter_map (try_load_template template_dir)

let () =
  match Sys.argv |> Array.to_list |> List.tl with
  | [template_dir; image_file] ->
      Printf.eprintf "Loading templates from %s...\n%!" template_dir;
      let templates = load_templates template_dir in
      Printf.eprintf "Loaded %d templates\n%!" (List.length templates);
      if templates = [] then (
        Printf.eprintf "Error: No templates loaded\n";
        exit 1
      );
      Printf.eprintf "Loading image %s...\n%!" image_file;
      let img = Png.load image_file [] in
      let arr = image_to_array img in
      let min_v, max_v = image_stats_from_array arr in
      let threshold = (min_v + max_v) / 2 in
      let x0, y0 = find_digit_origin arr min_v max_v threshold in
      Printf.eprintf "Image stats: min=%d, max=%d, threshold=%d\n%!"
        min_v max_v threshold;
      Printf.eprintf "Digit origin: (%d, %d)\n%!" x0 y0;
      let result = recognize_digit img templates in
      Printf.printf "Recognized: %s (confidence: %.3f)\n"
        result.recognized_digit result.confidence
  | _ ->
      Printf.eprintf "Usage: %s <template_dir> <image.png>\n" Sys.argv.(0);
      Printf.eprintf "  Uses direct pixel comparison (%dx%d block)\n"
        template_width template_height;
      exit 1
