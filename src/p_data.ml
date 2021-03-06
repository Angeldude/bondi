(*** p_data.ml *)

(* describing the results of parsing *)

open List
open Format
open Datum

type identifier = string
type tyVar =
    TyVar of string
  | MTypeVar of int
type p_type =
  | PtyV of tyVar
  | Pconstant of string
  | PapplyF of p_type * p_type
  | Pfunty of p_type * p_type
  | Plinty of p_type
  | Pquant of tyVar * p_type
  | Pnestedclass of string * p_type list * p_type (* for DNode <a> [b] *)
  | Pref of p_type
  | Parr of p_type
type p_term =
  | Ptvar of identifier
  | Pwildcard of string
    (* the empty string represents a true wildcard,
       "Int" etc are for datum wildcards.
       Anything else could appear here, and must be handled downstream *)
  | Pconstructor of identifier
  | Pdatum of datum_value
  | Poper of string * p_term list (* name and arguments *)
  | Papply of p_term * p_term
  | Plam of p_term * p_term list * p_term
  | Poperator of string
(*
  | Plin of p_term * p_term
*)
  | Pcases of p_case list
  | Paddcase of identifier * p_case
  | Psubcase of identifier
  | Plet of let_status * p_term * p_term * p_term
  | Ptyped of p_term * p_type
  | Pnew of string * p_type list
  | PnewArr of p_term * p_term
  | Pinvoke of p_term * identifier * bool (* a super ? *)
(*> CPC  *)
  | Pname of name_form * identifier
  | Pcname of name_form * identifier
  | Pdname of name_form * p_term
  | Pparr of p_term * p_term
  | Prest of identifier * p_term
  | Prepl of p_term
  | Ppcase of p_term * p_term
and name_form = Variable | Protected | Binding
(*< CPC *)
and let_status =
    Simple
| Recursive
| Extensible
| Linear
| Method
| Discontinuous
and p_case = identifier list option * p_term * p_type option * p_term
type add_case = identifier * p_case
type simple_datatype_declaration =
    p_type list * (identifier * p_type list) list
and datatype_declaration =
    string * simple_datatype_declaration list * add_case list

type show_mode = | Show_on | Show_off

and shell_action =
  | Let_decl of p_term * p_term
  | Lin_decl of p_term * p_term
  | Let_type_synonym of string * p_type
	(* type synonyms *)
  | Let_type of datatype_declaration
	(* type abstractors *)
  | Let_class of
      string * tyVar list * string option *
	((p_term list * (let_status * identifier * p_term) list) * add_case list)
  | Directive of string * string

exception PtypeError of p_type list * string;;
exception PTermError of p_term list * string

let pTypeError tys s = raise (PtypeError (tys,s));;
let pTermError ts s = raise (PTermError (ts,s));;


(*** types *)

let tyVarCounter = ref 0
let next_ty_count () = incr tyVarCounter;!tyVarCounter;;
let nextTypeVar() = MTypeVar(next_ty_count());;

let pconstTy str = Pconstant str
let pApF ty1 ty2 = PapplyF(ty1,ty2);;
let pclass (x,y,z) = Pnestedclass(x,y,z) ;;



    (* terms *)

let zvar x  = Ptvar x
let p_datum d = Pdatum d
let ap f x = Papply(f,x)
let ap2 f x y = ap (ap f x) y
let lam p t = Plam(p,[],t) ;;
let multilam ps r =
match ps with
| [] -> r
| p::ps1 -> Plam(p, ps1, r)
(*> CPC *)
let multirest = List.fold_right (fun n p -> Prest(n,p));;
(*< CPC *)
(*
let lin p t = Pli(p,t) ;;
let multilin = List.fold_right lin ;;
*)

let version_number =  System.version;;

(*** Modes *)

let show_off = Show_off
let show_on = Show_on

(* The optimisations are all beneficial. The mode switches are there to allow
     quantification of their benefits. *)

let modes = ref [               (* list of string/default pairs *)
  "declaration", show_on;       (* do show type of declared entity *)
  "echo",       show_off;       (* do not echo redirected standard input *)
  "eval",       show_on;        (* evaluate *)
  "infer",      show_off;       (* do not display inferred term *)
  "number",     show_off;       (* put line numbers on echoed lines *)
  "parse",      show_off;       (* do not display parse trees *)
  "prompt",     show_off;       (* do not show a prompt *)
  "specialise", show_off;       (* hide specialisation details *)
  "types",      show_on;         (* use types *)
  "nomatch",    show_off;        (* match failure as a bondi exception not an ocaml exception *)
  "declaration_index", show_off (* show the declaration index when formatting *)
] ;;


let is_nonempty_prefix s1 s2 =  (* prefixes of mode names will suffice *)
  let s1_len = String.length s1
  and s2_len = String.length s2
  in
  if s1_len = 0 || s1_len > s2_len
  then false
  else s1 = String.sub s2 0 s1_len
;;

let set_mode s mode =
  let rec loop = function
      [] -> basicError ("no such mode: " ^ s)
    | (name,curr)::t ->
        if is_nonempty_prefix s name
        then (name,mode)::t
        else (name,curr)::(loop t)
  in
  modes := loop (!modes);
;;

let safe_set_mode s mode =
  try set_mode s mode with
    Error message -> print_endline ("Warning: " ^ message)

let get_mode s =
  try List.assoc s !modes
  with Not_found -> basicError "unrecognised mode"
;;

let parse_modes s0 =
  let s = s0 ^ " " in
  let l = String.length s in
  let badly_formed = ref false in
  let rec parse i =
    if i == l then () else match s.[i] with
      ' '|':' -> parse (succ i)
    | '-' -> set show_off (succ i) (succ i)
    | '+' -> set show_on (succ i) (succ i)
    | _ -> badly_formed := true
  and set setting i j =
    match s.[j] with
      'A'..'Z'|'a'..'z'|'_' -> set setting i (succ j)
    | _ -> set_mode (String.sub s i (j - i)) setting; parse j
  in
  parse 0;
  if !badly_formed then print_endline "Warning: badly formed mode list";
  ()




(*** Command line *)

let help_text =
  Printf.sprintf "Usage: %s [OPTION]... [FILE]...%s%s%s%s%s%s"
    Sys.argv.(0)
    "\n  -e, --errorstopmode   Abort with nonzero exit code on any error"
    "\n  -f, --fast            Do not load the standard prelude"
    "\n  -h, --hide MODE       Set MODE to Show_off"
    "\n  -s, --show MODE       Set MODE to Show_on"
    "\n      --help            Display this help and exit"
    "\n      --version         output version information and exit"

let print_and_exit s =
  print_endline s;
  flush stdout;
  exit 0

type command_line = {
    mutable cl_std : bool;              (* Load the standard prelude? *)
    mutable cl_errorstopmode : bool;    (* Halt on any error? *)
    mutable cl_files : string list;     (* Files to run *)
  }

let parse_command_line argv =
  let cl =
    { cl_std = true;
      cl_errorstopmode = false;
      cl_files = [] }
  in
  let rec parse = function
      [] -> cl.cl_files <- List.rev cl.cl_files
    | "--" :: more -> cl.cl_files <- List.rev_append cl.cl_files more
    | "" :: tail -> parse tail
    | filename :: tail when filename.[0] != '-' ->
        cl.cl_files <- filename :: cl.cl_files; parse tail
    | "--version" :: _ -> print_and_exit ("bondi v. " ^ version_number)
    | "--help" :: _ -> print_and_exit help_text
    | ("-e"|"--errorstopmode") :: tail ->
        cl.cl_errorstopmode <- true; parse tail
    | ("-f"|"--fast") :: tail -> cl.cl_std <- false; parse tail
    | ("-h"|"--hide")::mode :: tail -> safe_set_mode mode show_off; parse tail
    | ("-s"|"--show")::mode :: tail -> safe_set_mode mode show_on; parse tail
    | option :: tail ->
        print_endline ("Warning: ignoring option " ^ option); parse tail
  in
  parse (List.tl (Array.to_list argv));
  cl



(*** formatting *)

let pf s = Printf.printf "%s\n" s;flush stdout ;;
let ps = Format.print_string;;
let lpn() = ps "(" ;;
let rpn() = ps ")" ;;


(* tidying - general, but first used with functors *)

let incrStringCounter ctr minc maxc = (* for incrementing term and type variables *)
  let ndx = ref (String.length ctr - 1)
  and flag = ref false
  and newCtr = Bytes.of_string ctr
  in
  while (!ndx >= 0 && !flag = false) do (* CHANGED & to && !!!! *)
    flag := true;
    let c = Char.chr ((Char.code (Bytes.get newCtr !ndx)) + 1)
    in
    if c <= maxc
    then
      Bytes.set newCtr !ndx c
    else (* carry *)
      (flag := false;
       Bytes.set newCtr !ndx minc;
       ndx := !ndx - 1)
  done;
  if (!flag = false) (* need to extend string *)
  then
    (String.make 1 minc) ^ Bytes.to_string newCtr
  else
    Bytes.to_string newCtr
;;

let rec format_identifier bound str =
  if List.mem str bound
  then ps "'";
  ps str
;;

let string_of_tyvar =
  function
    TyVar s -> s
  | MTypeVar n -> "ty_"^(string_of_int n)
;;

let rec format_p_type = function

    PtyV x -> ps (string_of_tyvar x)

  | Pconstant x -> ps x

  | PapplyF(ty1,ty2) ->
      format_p_type ty1;
      ps " ";
      format_p_type ty2

  | Pfunty (ty1,ty2) ->
      format_p_type ty1;
      ps " -> ";
      format_p_type ty2

  | Plinty ty ->
      ps "lin ";
      format_p_type ty

  | Pquant (x,ty2) ->
      ps ("all "^(string_of_tyvar x)^".");
      format_p_type ty2

  | Pnestedclass(str,tys,ty2) ->
      ps (str^ "<");
      format_p_types tys;
      ps ">" ;
      ps "[";
      format_p_type ty2;
      ps "]"
  | Pref ty ->
      ps "ref " ;
      format_p_type ty

  | Parr ty ->
      ps "array " ;
      format_p_type ty

and format_p_types = function
  [] -> ()
  | [ty] -> format_p_type ty
  | ty :: tys1 -> format_p_type ty ; ps "," ; format_p_types tys1
;;

let p_peek_type pty msg =
  format_p_type pty;
  print_flush();
  pf (" is " ^msg) ;
  print_flush()
;;



(*** term formatting *)

let rec format_identifiers = function
    [] -> ()
  | [x] -> ps x
  | x:: xs -> ps x; ps ","; format_identifiers xs


let rec format_p_term = function

   | Ptvar x
   | Pconstructor x -> ps x
   | Pwildcard str -> ps ("_"^str)
   | Pdatum d -> ps (string_of_datum_value d)

   | Poper(str,ts) ->
       ps str;
       let f t = lpn(); format_p_term t; rpn() in
       List.iter f ts

   | Papply(f,u) ->
       lpn();
       format_p_term f;
       rpn();
       lpn();
       format_p_term u;
       rpn()

   | Plam (p,ps1,s) ->
       ps "fun ";
       format_p_term p;
       let f t = format_p_term t in
       List.iter f ps1;
       ps " -> ";
       format_p_term s

   | Poperator s -> ps s (* the string names the operator *)

(*
   | Plin (p,s) ->
       ps "fun ";
       format_p_term p;
       ps " --> ";
       format_p_term s
*)

   | Pcases cases ->
       let rec format_case (xs_opt,p,_,s) =
	 match xs_opt with
	   None ->
	     format_p_term p;
	     ps " -> ";
	     format_p_term s
	 | Some xs ->
	     ps "{";
	     iter (fun x -> ps x; ps ",") xs;
	     ps "} ";
	     format_p_term p;
	     ps " -> ";
	     format_p_term s
       in
       lpn();
       List.iter format_case cases;
       rpn()

   | Paddcase (x,case) ->
     ps (x ^ " += ");
     format_p_term (Pcases[case])

   | Psubcase x ->
     ps ("generalise" ^ x)

   | Plet (status,x,t1,t2) ->
       ps "let <status> ";
       format_p_term x;
       ps " = ";
       format_p_term t1;
       ps " in ";
       format_p_term t2;

(* delete ?
   | Pletrec (x,t1,t2) ->
       ps "let rec ";
       format_p_term x;
       ps " = ";
       format_p_term t1;
       ps " in ";
       format_p_term t2;

   | Pletext (x,t1,t2) ->
       ps "let ext ";
       format_p_term x;
       ps " = ";
       format_p_term t1;
       ps " in ";
       format_p_term t2;

   | Pletmethod (x,t1,t2) ->
       ps "let method ";
       format_p_term x;
       ps " = ";
       format_p_term t1;
       ps " in ";
       format_p_term t2;
*)
   | Ptyped (t'',ty) ->
       lpn();
       format_p_term t'' ;
       ps " : ";
       format_p_type ty;
       rpn()

   | Pnew (str,tys) ->
       ps "new ";
       ps str;
       ps "<" ;
       format_p_types tys;
       ps ">"

   | Pinvoke (t,x,super) ->
       format_p_term t ;
       if super
       then ps ".super"
       else () ;
       ps ("."^x)

   | PnewArr(t,n)  ->
       ps "newarray ";
       format_p_term t;
       ps " ";
       format_p_term n

(*> CPC *)
  | Pdname (ty,d) -> (if ty = Protected then ps"~" else ());format_p_term d
  | Pcname (ty,id)
  | Pname (ty,id) ->
      let formd =
        match ty with
        | Variable -> id
        | Protected -> "~" ^ id
        | Binding -> "\\" ^ id
      in
      ps formd

  | Pparr(p1,p2) -> lpn();format_p_term p1;ps ") | (";format_p_term p2;rpn()

  | Prest (id,p) -> ps ("(v " ^ id ^ ")"); format_p_term p

  | Prepl (p) -> ps "!(";format_p_term p;ps ")"

  | Ppcase (p,s) -> (lpn();format_p_term p; ps " -> "; format_p_term s;rpn())
(*< CPC *)

and p_peek t str =
  format_p_term t ;
  print_flush();
  pf (" is " ^ str);
  print_flush()

and p_peeks ts str = List.iter (fun x -> p_peek x str) ts


let formatPTermError (ts,s) =

  ps ("term error: ");

  let form_in_box t =
    try
      format_p_term t;
    with _ -> pf "cannot format term error"
  in

  match ts with
    [t] ->
      form_in_box t;
      ps (" "^s);
      print_newline()

  | [t1;t2] ->
      form_in_box t1;
      ps " and ";
      form_in_box t2;
      ps (" "^s);
      print_newline()

  | [t1;t2;t3] ->
      form_in_box t1;
      ps " and ";
      form_in_box t2;
      ps " and ";
      form_in_box t3;
      ps (" "^s);
      print_newline()

  | _ -> pf "unformatted term error"
;;
