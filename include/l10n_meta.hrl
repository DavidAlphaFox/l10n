% vim: set filetype=erlang shiftwidth=4 tabstop=4 expandtab tw=80:

%%% =====================================================================
%%%   Copyright 2011 Uvarov Michael 
%%%
%%%   Licensed under the Apache License, Version 2.0 (the "License");
%%%   you may not use this file except in compliance with the License.
%%%   You may obtain a copy of the License at
%%%
%%%       http://www.apache.org/licenses/LICENSE-2.0
%%%
%%%   Unless required by applicable law or agreed to in writing, software
%%%   distributed under the License is distributed on an "AS IS" BASIS,
%%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%%   See the License for the specific language governing permissions and
%%%   limitations under the License.
%%%
%%% $Id$
%%%
%%% @copyright 2010-2011 Michael Uvarov
%%% @author Michael Uvarov <freeakk@gmail.com>
%%% =====================================================================

-export([get_path/2, get_file/2, get_type/0, get_name/1, source_files/0,
		get_store_server_name/1]).
-export([start_link/0]).

-ifdef(L10N_TYPE_FORMAT).
-export([format/2]).
-endif.

-ifdef(L10N_TYPE_STRING).
-export([string/1]).
-endif.

-export([generate/1]).
-export([string_to_object/1]).

% Protected
-export([is_available/1]).

-ifndef(L10N_SERVER).
-define(L10N_SERVER, ?MODULE).
-endif.

-ifndef(L10N_TABLE).
-define(L10N_TABLE, ?MODULE).
-endif.

-ifndef(L10N_TYPE).
    -ifdef(L10N_TYPE_FORMAT).
    -define(L10N_TYPE, 'format').
    -endif.

    -ifdef(L10N_TYPE_STRING).
    -define(L10N_TYPE, 'string').
    -endif.
-endif.

-ifndef(L10N_TO_OBJECT).
    -ifdef(L10N_TYPE_FORMAT).
    -define(L10N_TO_OBJECT(X), l10n_utils:format(X)).
    -endif.

    -ifdef(L10N_TYPE_STRING).
    -define(L10N_TO_OBJECT(X), l10n_utils:string(X)).
    -endif.
-endif.

-ifdef(L10N_APPLICATION).
-define(L10N_PATH(T, L),
	begin	
		code:priv_dir(?L10N_APPLICATION) ++ "/translates/" 
			++ ?MODULE_STRING ++ "/"
			++ atom_to_list(L) ++ "." ++ atom_to_list(T)
	end).

-define(L10N_LOCALES,
	begin	
		DirName = code:priv_dir(?L10N_APPLICATION) ++ "/translates/" 
			++ ?MODULE_STRING,
		Files = filelib:wildcard(DirName ++ "/*.po"),
    	[ list_to_atom(filename:basename(X, ".po")) || X <- Files ]
	end).

-define(L10N_SOURCE,
	begin
    	DirName = code:lib_dir(?L10N_APPLICATION, src),
    	filelib:wildcard(DirName ++ "/*.erl")
	end).
-endif.


-type l10n_file_type() :: 'po' | 'pot'.
-type l10n_locale() :: atom().

-spec get_path(l10n_file_type(), l10n_locale()) -> string().
get_path(Type, Locale) ->
	?L10N_PATH(Type, Locale).

get_name('domain') -> ?MODULE;
get_name('table')  -> ?L10N_TABLE;
get_name('server') -> ?L10N_SERVER.

%% @doc Get the name of l10n_store_server with locale=L.
get_store_server_name(L) -> 
	list_to_atom(lists:flatten([?MODULE_STRING, $[, atom_to_list(L), $]])).

source_files() ->
	?L10N_SOURCE.

%% format | string
get_type() -> ?L10N_TYPE.


available_locales() ->
	?L10N_LOCALES.

is_available(L) ->
	F = get_path('po', L),
	filelib:is_file(F).

%% @doc Start the store server.
start_link() ->
	l10n_spawn_server:start_link(?MODULE).

string_to_object(S) ->
    ?L10N_TO_OBJECT(S).


-ifdef(L10N_TYPE_FORMAT).
format(Id, Params) ->
	H = l10n_utils:hash(Id),
	format(H, Id, Params).

format(H, Id, Params) ->
	Fmt = case search(H, 5) of
		false -> 
			X = l10n_utils:format(Id), 
			insert(H, X),
			X;
		X -> X
		end,
	i18n_message:format(Fmt, Params).
-endif.
	
-ifdef(L10N_TYPE_STRING).
string(Id) ->
	H = l10n_utils:hash(Id),
	string(H, Id).

%% @doc Try to search a string in the data store.
%%		If the string is not found, add it.
string(H, Id) ->
	?L10N_TYPE = 'string',
	H = l10n_utils:hash(Id),
	case search(H, 5) of
	[] ->
		X = l10n_utils:string(Id), 
		insert(H, X),
		X;
	[{_,X}] -> X
	end.
-endif.

%% @doc Retrieve Hash(Key) from the data store.
search(H, Count) 
	when Count > 0 ->
	try
		T = get(?L10N_TABLE),
		ets:lookup(T, H)
	catch error:_ ->
		L = l10n_locale:get_locale(),
		get_table(L),
		search(H, Count - 1)
	end.

%% @doc Put the locale table id of the data store to the process dictionary.
%%		Return table id.		
get_table(L) ->
	P = l10n_spawn_server:find_store(?MODULE, L),
	T = l10n_store_server:get_table(P),
	put(?L10N_TABLE, T),
	% When user calls l10n_locale:set_locale(...),
	% this tid will be erased.
	l10n_locale:add_domain(?MODULE),
	T.


%% @doc Send {Key, Value} to the store server.
insert(Key, Value) ->
	L = l10n_locale:get_locale(),
	P = l10n_spawn_server:find_store(?MODULE, L),
	l10n_store_server:update_value(P, Key, Value).
	
%% @doc Writes parsed data to files.
generate('pot') ->
	Values = l10n_parser:parse(?MODULE),
	IOList = l10n_export:to_pot(Values),
	FileName = get_path('pot', 'root'),
	ok = filelib:ensure_dir(FileName),
	l10n_utils:file_write(FileName, IOList),
	ok;
	
generate('po') ->
	SRC = l10n_parser:parse(?MODULE),
	Locales = available_locales(),
	F = fun(L) ->
		PO = get_file('po', L),
		IOList = l10n_export:to_po(PO, SRC),
		FileName = get_path('po', L),
		l10n_utils:file_write(FileName, IOList)
		end,
	lists:map(F, Locales),
	ok.

%% @doc Extract PO data from file.
get_file('po', Locale) ->
	FileName = get_path('po', Locale),
	l10n_import:from_po(FileName).
	
