using System;
using System.Collections;
using System.Diagnostics;

using IDE;
using IDE.ui;
using IDE.Compiler;

namespace BeefLsp {
	class Lsp : ILspHandler {
		private Connection connection = new .(this) ~ delete _;
		private LspApp app = new .() ~ delete _;

		private DocumentManager documents = new .() ~ delete _;
		private List<String> sentDiagnosticsUris = new .() ~ DeleteContainerAndItems!(_);

		public void Start() {
			app.Init();
			connection.Start();
		}

		private Result<Json> OnInitialize(Json args) {
			StringView workspacePath = args["rootPath"].AsString; // TODO: Also check rootUri which should have higher priority
			app.LoadWorkspace(workspacePath);

			// Response
			Json res = .Object();

			Json cap = .Object();
			res["capabilities"] = cap;

			Json documentSync = .Object();
			cap["textDocumentSync"] = documentSync;
			documentSync["openClose"] = .Bool(true);
			documentSync["change"] = .Number(1); // Full sync

			cap["foldingRangeProvider"] = .Bool(true);

			Json completionProvider = .Object();
			cap["completionProvider"] = completionProvider;
			completionProvider["triggerCharacters"] = .Array()..Add(.String("."));

			Json documentSymbolProvider = .Object();
			cap["documentSymbolProvider"] = documentSymbolProvider;
			documentSymbolProvider["label"] = .String("Beef Lsp");

			Json signatureHelpProvider = .Object();
			cap["signatureHelpProvider"] = signatureHelpProvider;
			signatureHelpProvider["triggerCharacters"] = .Array()..Add(.String("("));
			signatureHelpProvider["retriggerCharacters"] = .Array()..Add(.String(","));

			cap["hoverProvider"] = .Object();

			cap["definitionProvider"] = .Object();

			Json info = .Object();
			res["serverInfo"] = info;
			info["name"] = .String("beef-lsp");
			info["version"] = .String("0.1.0");

			return res;
		}

		private void OnInitialized() {
			app.mBfBuildSystem.Lock(0);
			defer app.mBfBuildSystem.Unlock();

			// Generate initial diagnostics
			BfPassInstance pass = app.mBfBuildSystem.CreatePassInstance("IntialParse");
			defer delete pass;

			app.InitialParse(pass);

			BfResolvePassData passData = .Create(.None);
			defer delete passData;

			app.compiler.ClassifySource(pass, passData);

			Send("beef/initialized", Json.Null());

			PublishDiagnostics(pass);
		}

		private void PublishDiagnostics(BfPassInstance pass) {
			// Get json errors
			int32 count = pass.GetErrorCount();
			Dictionary<String, List<Json>> files = new .();

			for (int32 i < count) {
				BfPassInstance.BfError error = scope .();
				pass.GetErrorData(i, error, true);

				List<Json> diagnostics = files.GetValueOrDefault(error.mFilePath);
				if (diagnostics == null) diagnostics = files[new .(error.mFilePath)] = new .();

				Json? json = GetDiagnostic(error);
				if (json.HasValue) diagnostics.Add(json.Value);
			}

			// Send diagnostics
			List<String> uris = scope .();

			for (let file in files) {
				Json json = .Object();

				String uri = new $"file:///{file.key}";
				json["uri"] = .String(uri);

				Json diagnostics = .Array();
				json["diagnostics"] = diagnostics;
				file.value.CopyTo(diagnostics.AsArray);

				Send("textDocument/publishDiagnostics", json);
				uris.Add(uri);
			}

			// Clear diagnostics for URIs that were sent last time but not this time
			for (let uri in sentDiagnosticsUris) {
				if (uris.Contains(uri)) continue;

				Json json = .Object();
				json["uri"] = .String(uri);
				json["diagnostics"] = .Array();

				Send("textDocument/publishDiagnostics", json);
			}

			sentDiagnosticsUris.ClearAndDeleteItems();
			uris.CopyTo(sentDiagnosticsUris);

			// Cleanup
			DeleteDictionaryAndKeysAndValues!(files);
		}

		private Json? GetDiagnostic(BfPassInstance.BfError error) {
			Document document = documents.Get(error.mFilePath);
			if (document == null) return null;

			Json json = .Object();

			LineInfo startLineInfo = document.GetLineInfo(error.mSrcStart);
			LineInfo endLineInfo = document.GetLineInfo(error.mSrcEnd);

			json["range"] = Range(startLineInfo.line, error.mSrcStart - startLineInfo.start, endLineInfo.line, error.mSrcEnd - endLineInfo.start);
			json["severity"] = .Number(error.mIsWarning ? 2 : 1);
			json["code"] = .Number(error.mCode);
			json["message"] = .String(error.mError);

			return json;
		}

		private Json Range(int startLine, int startCharacter, int endLine, int endCharacter) {
			Json start = .Object();
			start["line"] = .Number(startLine);
			start["character"] = .Number(startCharacter);

			Json end = .Object();
			end["line"] = .Number(endLine);
			end["character"] = .Number(endCharacter);

			Json json = .Object();
			json["start"] = start;
			json["end"] = end;

			return json;
		}

		private void OnDidOpen(Json args) {
			Json j = args["textDocument"];

			// Get path
			String path = scope .();
			if (!GetPath(j["uri"].AsString, path)) return;

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return;

			// Add
			String contents = new .();
			j["text"].AsString.Unescape(contents);

			Document document = documents.Add(path, (.) j["version"].AsNumber, contents);

			// Parse
			ParseDocument(document);
		}

		private void OnDidChange(Json args) {
			// Get path
			String path = scope .();
			if (!GetPath(args["textDocument"]["uri"].AsString, path)) return;

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return;

			// Get contents
			StringView contentsRaw;
			Json jsonContents = args["contentChanges"][0];
			if (jsonContents.IsString) contentsRaw = jsonContents.AsString;
			else contentsRaw = jsonContents["text"].AsString;

			String contents = scope .(contentsRaw.Length);
			contentsRaw.Unescape(contents);

			// Update document
			Document document = documents.Get(path);
			document.SetContents((.) args["textDocument"]["version"].AsNumber, contents);

			// Parse
			ParseDocument(document);
		}

		private void ParseDocument(Document document) {
			app.mBfBuildSystem.Lock(0);
			defer app.mBfBuildSystem.Unlock();

			ProjectSource source = app.FindProjectSourceItem(document.path);
			BfParser parser = app.mBfBuildSystem.CreateParser(source);

			BfPassInstance pass = app.mBfBuildSystem.CreatePassInstance("Parse");
			defer delete pass;

			parser.SetSource(document.contents, document.path, -1);
			parser.Parse(pass, false);
			parser.Reduce(pass);
			parser.BuildDefs(pass, null, false);

			// Classify
			BfResolvePassData passData = .Create(.None);
			defer delete passData;

			app.compiler.ClassifySource(pass, passData);

			// Publish diagnostics
			PublishDiagnostics(pass);
		}

		private bool GetPath(StringView uri, String buffer) {
			if (!uri.StartsWith("file:///")) {
				Console.WriteLine("Invalid URI, only file:/// URIs are supported: %s", uri);
				return false;
			}

			buffer.Set(uri[8...]);
			buffer.Replace("%3A", ":");
			IDEUtils.FixFilePath(buffer);
			if (buffer[1] == ':' && buffer[2] == '\\' && buffer[3] != '\\') buffer.Insert(2, '\\');

			return true;

		}

		private void OnDidClose(Json args) {
			// Get path
			String path = scope .();
			if (!GetPath(args["textDocument"]["uri"].AsString, path)) return;

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return;

			// Remove
			documents.Remove(path);
		}

		private Result<Json> OnFoldingRange(Json args) {
			// Get path
			String path = scope .();
			if (!GetPath(args["textDocument"]["uri"].AsString, path)) return Json.Null();

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return Json.Null();

			// Get folding range data
			app.mBfBuildSystem.Lock(0);
			defer app.mBfBuildSystem.Unlock();

			Document document = documents.Get(path);
			BfParser parser = app.mBfBuildSystem.FindParser(source);

			var resolvePassData = parser.CreateResolvePassData(.None);
			defer delete resolvePassData;

			String collapseData = app.compiler.GetCollapseRegions(parser, resolvePassData, "", .. scope .());

			// Parse data to json
			Json ranges = .Array();

			for (var line in Lines(collapseData)) {
				let original = line;

				// Parse folding range
				SourceEditWidgetContent.CollapseEntry.Kind kind = (.) line[0];
				line.RemoveFromStart(1);

				var it = line.Split(',');
				int start = int.Parse(it.GetNext().Value);
				int end = int.Parse(it.GetNext().Value);

				if (it.HasMore) {
					Console.WriteLine("Unknown folding range data '{}'", original);
					continue;
				}

				LineInfo startLine = document.GetLineInfo(start);
				LineInfo endLine = document.GetLineInfo(end);

				// Create json
				Json json = .Object();
				ranges.Add(json);

				json["startLine"] = .Number(startLine.line);
				//json["startCharacter"] = .Number(startLine.start - start);
				json["endLine"] = .Number(endLine.line - 1);
				//json["endCharacter"] = .Number(endLine.start - end);

				switch (kind) {
				case .Comment: json["kind"] = .String("comment");
				case .Region:  json["kind"] = .String("region");
				default:       json["kind"] = .String(kind.ToString(.. scope .()));
				}
			}

			return ranges;
		}

		private Result<Json> OnCompletion(Json args) {
			// Get path
			String path = scope .();
			if (!GetPath(args["textDocument"]["uri"].AsString, path)) return Json.Null();

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return Json.Null();

			// Get completion data
			app.mBfBuildSystem.Lock(0);
			defer app.mBfBuildSystem.Unlock();
			
			Document document = documents.Get(path);

			int cursor = document.GetCharacter((.) args["position"]["line"].AsNumber, (.) args["position"]["character"].AsNumber);

			String completionData = GetCompilerData(document, .Completions, cursor, .. scope .());
			
			// Parse data to json
			Json items = .Array();

			int start = -1;
			int end = -1;

			for (let line in Lines(completionData)) {
				// Parse completion item
				var it = line.Split('\t');
				StringView type = it.GetNext().Value;

				int kind = -1;

				switch (type) {
				case "method":      kind = 2;
				case "extmethod":   kind = 2;
				case "field":       kind = 5;
				case "property":    kind = 10;
				case "namespace":   kind = 9;
				case "class":       kind = 7;
				case "interface":   kind = 8;
				case "valuetype":   kind = 22;
				case "object":      kind = 5;
				case "pointer":     kind = 18;
				case "value":       kind = 12;
				case "payloadEnum": kind = 20;
				case "generic":     kind = 1;
				case "folder":      kind = 19;
				case "file":        kind = 17;
				case "mixin":       kind = 2;
				case "token":       kind = 14;
				}

				if (kind == -1) {
					switch (type) {
					case "insertRange":
						var it2 = it.GetNext().Value.Split(' ');
						start = int.Parse(it2.GetNext().Value);
						end = int.Parse(it2.GetNext().Value);
					default: Console.WriteLine("Unknown completion type: {}", line);
					}

					continue;
				}

				if (start == -1) {
					Console.WriteLine("Tried to create completion item before 'insertRange' was detected");
					continue;
				}

				StringView text = it.GetNext().Value;

				int matchesPos = text.IndexOf('\x02');
				if (matchesPos != -1) {
					text = text[0...matchesPos - 1];
				}

				int docPos = text.IndexOf('\x03');
				if (docPos != -1) {
					text = text[0...docPos - 1];
				}

				// Create json
				Json json = .Object();
				items.Add(json);

				json["label"] = .String(text);
				json["kind"] = .Number(kind);
			}

			return items;
		}

		struct Symbol : this(StringView name, int kind, int line, int column) {}
		class SymbolGroup {
			public Symbol symbol;

			public List<SymbolGroup> groups = new .() ~ delete _;
			public List<Symbol> symbols = new .() ~ delete _;

			public this(Symbol symbol) {
				this.symbol = symbol;
			}
		}

		private Result<Json> OnDocumentSymbol(Json args) {
			// Get path
			String path = scope .();
			if (!GetPath(args["textDocument"]["uri"].AsString, path)) return Json.Null();

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return Json.Null();

			// Get navigation data
			app.mBfBuildSystem.Lock(0);
			defer app.mBfBuildSystem.Unlock();
			
			Document document = documents.Get(path);

			String navigationData = GetCompilerData(document, .Navigation, 0, .. scope .());

			// Parse data
			List<Symbol> symbols = scope .();

			for (let line in Lines(navigationData)) {
				// Parse symbol
				var it = line.Split('\t', .RemoveEmptyEntries);

				StringView name = it.GetNext().Value;
				StringView type = it.GetNext().Value;
				int line = int.Parse(it.GetNext().Value);
				int column = int.Parse(it.GetNext().Value);

				int kind;

				switch (type) {
				case "method":    kind = 6;
				case "extmethod": kind = 6;
				case "property":  kind = 7;
				case "class":     kind = 5;
				case "enum":      kind = 10;
				case "struct":    kind = 23;
				case "typealias": kind = 26; // TODO: Currently set to TypeParameter
				default:
					Console.WriteLine("Unknown navigation data: {}", line);
					continue;
				}

				symbols.Add(.(name, kind, line, column));
			}

			// Create symbol hierarchy
			Dictionary<StringView, SymbolGroup> groups = scope .();
			defer { for (let group in groups.Values) delete group; }

			mixin GetSymbol(StringView name) {
				Symbol symbol = default;

				for (let sym in symbols) {
					if (sym.name == name) {
						symbol = sym;
						break;
					}
				}

				symbol
			}

			for (let symbol in symbols) {
				int index = SymbolGetLastDotIndex!(symbol);

				SymbolGroup prevGroup = null;
				bool first = true;
				
				while (index != -1) {
					StringView groupName = symbol.name[0...index - 1];

					SymbolGroup group = groups.GetValueOrDefault(groupName);
					if (group == null) groups[groupName] = group = new .(GetSymbol!(groupName));

					if (prevGroup != null && !group.groups.Contains(prevGroup)) {
						group.groups.Add(prevGroup);

						for (let sym in group.symbols) {
							if (sym.name == prevGroup.symbol.name) {
								@sym.Remove();
								break;
							}
						}
					}

					index = groupName.LastIndexOf('.');
					prevGroup = group;

					if (first) {
						group.symbols.Add(symbol);
						first = false;
					}
				}
			}

			// Create json
			Json jsonSymbols = .Array();

			for (let group in groups.Values) {
				if (group.symbol.name.Contains('.')) continue;

				jsonSymbols.Add(SymbolGroupToJson(group));
			}

			return jsonSymbols;
		}

		private mixin SymbolGetLastDotIndex(Symbol symbol) {
			int parenIndex = symbol.name.IndexOf('(');

			int index;
			if (parenIndex == -1) index = symbol.name.LastIndexOf('.');
			else index = symbol.name[0...parenIndex - 1].LastIndexOf('.');

			index
		}

		private Json SymbolGroupToJson(SymbolGroup group) {
			Json json = SymbolToJson(group.symbol);

			if (!group.groups.IsEmpty || !group.symbols.IsEmpty) {
				Json children = .Array();
				json["children"] = children;

				// Groups
				for (let childGroup in group.groups) {
					children.Add(SymbolGroupToJson(childGroup));
				}

				// Symbols
				for (let childSymbol in group.symbols) {
					children.Add(SymbolToJson(childSymbol));
				}
			}

			return json;
		}

		private Json SymbolToJson(Symbol symbol) {
			Json json = .Object();

			int index = SymbolGetLastDotIndex!(symbol);

			json["name"] = .String(index == -1 ? symbol.name : symbol.name.Substring(index + 1));
			json["kind"] = .Number(symbol.kind);
			json["range"] = Range(symbol.line, symbol.column, symbol.line, symbol.column);
			json["selectionRange"] = Range(symbol.line, symbol.column, symbol.line, symbol.column);

			return json;
		}

		enum CompilerDataType {
			Completions,
			Navigation,
			Hover,
			GoToDefinition
		}

		private void GetCompilerData(Document document, CompilerDataType type, int character, String buffer) {
			ProjectSource source = app.FindProjectSourceItem(document.path);
			BfParser parser = app.mBfBuildSystem.CreateParser(source, false);

			String name;
			switch (type) {
			case .Completions:    name = "GetCompilerData - Completions";
			case .Navigation:     name = "GetCompilerData - Navigation";
			case .Hover:          name = "GetCompilerData - Hover";
			case .GoToDefinition: name = "GetCompilerData - GoToDefinition";
			}

			let pass = app.mBfBuildSystem.CreatePassInstance(name);
			defer delete pass;

			ResolveType resolveType;
			switch (type) {
			case .Completions:    resolveType = .Autocomplete;
			case .Navigation:     resolveType = .GetNavigationData;
			case .Hover:          resolveType = .GetResultString;
			case .GoToDefinition: resolveType = .GoToDefinition;
			}
			
			parser.SetIsClassifying();
			parser.SetSource(document.contents, document.path, -1);
			parser.SetAutocomplete(type == .Navigation ? -1 : character);

			let passData = parser.CreateResolvePassData(resolveType);
			defer delete passData;

			parser.Parse(pass, false);
			parser.Reduce(pass);
			parser.BuildDefs(pass, passData, false);
			app.compiler.ClassifySource(pass, passData);

			app.compiler.GetAutocompleteInfo(buffer);

			delete parser;
			app.mBfBuildSystem.RemoveOldData();
		}
		private static int Something(bool a, String b, int omg) => 159;

		private Result<Json> OnSignatureHelp(Json args) {
			// Get path
			String path = scope .();
			if (!GetPath(args["textDocument"]["uri"].AsString, path)) return Json.Null();

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return Json.Null();

			// Get signature data
			app.mBfBuildSystem.Lock(0);
			defer app.mBfBuildSystem.Unlock();

			Document document = documents.Get(path);

			int cursor = document.GetCharacter((.) args["position"]["line"].AsNumber, (.) args["position"]["character"].AsNumber);

			String signatureData = GetCompilerData(document, .Completions, cursor, .. scope .());

			// Parse data
			List<String> signatures = scope .();
			int activeSignature = -1;
			List<int> argumentPositions = scope .();

			defer signatures.ClearAndDeleteItems();

			loop: for (let line in Lines(signatureData)) {
				var it = line.Split('\t', .RemoveEmptyEntries);

				StringView type = it.GetNext().Value;
				StringView data = it.GetNext().Value;

				if (it.HasMore) {
					String str = scope:loop .(data);
					if (str.EndsWith('\x03')) {
						str.RemoveFromEnd(1);
						str.Append('\n');
					}

					for (let more in it) {
						let x03 = more.EndsWith('\x03');

						str.Append(x03 ? more[...^2] : more);
						str.Append('\n');
					}

					data = str;
				}

				switch (type) {
				case "invokeInfo":
					var it2 = data.Split(' ', .RemoveEmptyEntries);
					activeSignature = int.Parse(it2.GetNext().Value);

					for (let argumentPosition in it2) {
						argumentPositions.Add(int.Parse(argumentPosition));
					}
				case "invoke":
					signatures.Add(new .(data));
				}
			}

			if (signatures.IsEmpty || activeSignature == -1) return Json.Null();

			// Calculate active parameter
			int activeParameter = 0;

			for (int i = 1; i < argumentPositions.Count; i++) {
				if (cursor > argumentPositions[i - 1] && cursor <= argumentPositions[i]) {
					activeParameter = i - 1;
					break;
				}
			}

			// Create json
			Json json = .Object();

			Json jsonSignatures = .Array();
			json["signatures"] = jsonSignatures;

			loop: for (let signature in signatures) {
				Json jsonSignature = .Object();
				jsonSignatures.Add(jsonSignature);

				StringView label = scope String(signature)..Replace("\x01", "");
				StringView documentation = "";

				int documentationIndex = label.IndexOf('\x03');
				if (documentationIndex != -1) {
					documentation = ParseDocumentation(label.Substring(documentationIndex + 1), .. scope:loop .());
					label = label[0...documentationIndex - 1];

				}

				jsonSignature["label"] = .String(label);
				if (!documentation.IsEmpty) jsonSignature["documentation"] = .String(documentation);

				Json jsonParameters = .Array();
				jsonSignature["parameters"] = jsonParameters;

				for (let parameter in signature[signature.IndexOf('(') + 1...signature.LastIndexOf(')') - 1].Split('\x01', .RemoveEmptyEntries)) {
					Json jsonParameter = .Object();
					jsonParameters.Add(jsonParameter);

					jsonParameter["label"] = .String(parameter);
				}
			}

			json["activeSignature"] = .Number(activeSignature);
			json["activeParameter"] = .Number(activeParameter);

			return json;
		}

		private void ParseDocumentation(StringView documentation, String buffer) {
			for (let line in Lines(documentation)) {
				buffer.Append(line[3...]..TrimStart());
				if (@line.HasMore) buffer.Append('\n');
			}
		}

		private LineEnumerator Lines(StringView string) {
			return .(string.Split('\n', .RemoveEmptyEntries));
		}

		struct LineEnumerator : IEnumerator<StringView> {
			private StringSplitEnumerator enumerator;

			public this(StringSplitEnumerator enumerator) {
				this.enumerator = enumerator;
			}

			public bool HasMore => enumerator.HasMore;

			public Result<StringView> GetNext() mut {
				switch (enumerator.GetNext()) {
				case .Ok(let val): return val.EndsWith('\r') ? val[...^2] : val;
				case .Err:         return .Err;
				}
			}
		}

		private Result<Json> OnHover(Json args) {
			// Get path
			String path = scope .();
			if (!GetPath(args["textDocument"]["uri"].AsString, path)) return Json.Null();

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return Json.Null();

			// Get hover data
			app.mBfBuildSystem.Lock(0);
			defer app.mBfBuildSystem.Unlock();

			Document document = documents.Get(path);

			int cursor = document.GetCharacter((.) args["position"]["line"].AsNumber, (.) args["position"]["character"].AsNumber);

			String hoverData = GetCompilerData(document, .Hover, cursor, .. scope .());

			// Parse data
			if (hoverData.IsEmpty) return Json.Null();

			StringView hover = Lines(hoverData).GetNext().Value;
			if (!hover.StartsWith(':')) return Json.Null();

			hover.Adjust(1);
			if (hover.StartsWith("class ")) hover.Adjust(6);

			int documentationIndex = hover.IndexOf('\x03');
			StringView documentation = "";

			if (documentationIndex != -1) {
				String docs = scope .();

				for (let line in hover.Substring(documentationIndex + 1).Split('\t', .RemoveEmptyEntries)) {
					int a = 1;
					if (line.EndsWith('\x03')) a++;
					if (line.EndsWith("\r\x03")) a++;

					docs.Append(line[...^a]);
					docs.Append("  \n");
				}

				documentation = ParseDocumentation(docs, .. scope:: .());
				hover = hover[0...documentationIndex - 1];
			}

			// Create json
			Json json = .Object();

			Json contents = .Object();
			json["contents"] = contents;
			contents["kind"] = .String("markdown");
			contents["value"] = .String(documentation.IsEmpty ? hover : scope $"{hover}  \n  \n{documentation}");

			return json;
		}

		private Result<Json> OnDefinition(Json args) {
			// Get path
			String path = scope .();
			if (!GetPath(args["textDocument"]["uri"].AsString, path)) return Json.Null();

			ProjectSource source = app.FindProjectSourceItem(path);
			if (source == null) return Json.Null();

			// Get definition data
			app.mBfBuildSystem.Lock(0);
			defer app.mBfBuildSystem.Unlock();

			Document document = documents.Get(path);

			int cursor = document.GetCharacter((.) args["position"]["line"].AsNumber, (.) args["position"]["character"].AsNumber);

			String definitionData = GetCompilerData(document, .GoToDefinition, cursor, .. scope .());

			// Parse data
			StringView file = "";
			int line = 0;
			int column = 0;

			for (let data in Lines(definitionData)) {
				var it = data.Split('\t', .RemoveEmptyEntries);

				StringView type = it.GetNext().Value;
				if (type != "defLoc") continue;

				file = it.GetNext().Value;
				line = int.Parse(it.GetNext().Value);
				column = int.Parse(it.GetNext().Value);

				break;
			}

			// Create json
			if (file.IsEmpty) return Json.Null();

			Json json = .Object();

			json["targetUri"] = .String(scope $"file:///{file}");
			json["targetRange"] = Range(line, column, line, column);
			json["targetSelectionRange"] = Range(line, column, line, column);

			return json;
		}

		private Result<Json> OnShutdown() {
			Console.WriteLine("Shutting down");

			app.Stop();
			app.Shutdown();

			return Json.Null();
		}

		private void OnExit() {
			connection.Stop();
		}

		public void OnMessage(Json json) {
			StringView method = json["method"].AsString;
			Console.WriteLine("Received: {}", method);

			Json args = json["params"];

			switch (method) {
			case "initialize":                  HandleRequest(json, OnInitialize(args));
			case "initialized":                 OnInitialized();
			case "shutdown":                    HandleRequest(json, OnShutdown());
			case "exit":                        OnExit();

			case "textDocument/didOpen":        OnDidOpen(args);
			case "textDocument/didChange":      OnDidChange(args);
			case "textDocument/didClose":       OnDidClose(args);

			case "textDocument/foldingRange":   HandleRequest(json, OnFoldingRange(args));
			case "textDocument/completion":     HandleRequest(json, OnCompletion(args));
			case "textDocument/documentSymbol": HandleRequest(json, OnDocumentSymbol(args));
			case "textDocument/signatureHelp":  HandleRequest(json, OnSignatureHelp(args));
			case "textDocument/hover":          HandleRequest(json, OnHover(args));
			case "textDocument/definition":     HandleRequest(json, OnDefinition(args));
			}
		}

		private void HandleRequest(Json json, Result<Json> result) {
			Json response = .Object();

			response["jsonrpc"] = .String("2.0");
			response["id"] = json["id"];

			response["result"] = result;

			connection.Send(response);
			response.Dispose();
		}

		private void Send(StringView method, Json json) {
			Json notification = .Object();

			notification["jsonrpc"] = .String("2.0");
			notification["method"] = .String(method);
			notification["params"] = json;

			connection.Send(notification);
			notification.Dispose();
		}

		/*
		private void ParseSymbolData(String data, BfResolvePassData passData) {
			bool typeDef = false;

			for (let line in Lines(data)) {
				var lineDataItr = line.Split('\t');
				var dataType = lineDataItr.GetNext().Get();

				switch (dataType) {
				case "localId":
					int32 localId = int32.Parse(lineDataItr.GetNext().Get());
					passData.SetLocalId(localId);
				case "typeRef":
					passData.SetSymbolReferenceTypeDef(scope .(lineDataItr.GetNext().Get()));
					typeDef = true;
				case "fieldRef":
					passData.SetSymbolReferenceTypeDef(scope .(lineDataItr.GetNext().Get()));
					passData.SetSymbolReferenceFieldIdx(int32.Parse(lineDataItr.GetNext().Get()));
					typeDef = true;
				case "methodRef", "ctorRef":
					passData.SetSymbolReferenceTypeDef(scope .(lineDataItr.GetNext().Get()));
					passData.SetSymbolReferenceMethodIdx(int32.Parse(lineDataItr.GetNext().Get()));
					typeDef = true;
				case "invokeMethodRef":
					if (!typeDef) {
						passData.SetSymbolReferenceTypeDef(scope .(lineDataItr.GetNext().Get()));
						passData.SetSymbolReferenceMethodIdx(int32.Parse(lineDataItr.GetNext().Get()));
						typeDef = true;
					}
				case "propertyRef":
					passData.SetSymbolReferenceTypeDef(scope .(lineDataItr.GetNext().Get()));
					passData.SetSymbolReferencePropertyIdx(int32.Parse(lineDataItr.GetNext().Get()));
					typeDef = true;
				case "typeGenericParam":
					passData.SetTypeGenericParamIdx(int32.Parse(lineDataItr.GetNext().Get()));
				case "methodGenericParam":
					passData.SetMethodGenericParamIdx(int32.Parse(lineDataItr.GetNext().Get()));
				case "namespaceRef":
					passData.SetSymbolReferenceNamespace(scope .(lineDataItr.GetNext().Get()));
				}
			}
		}
		*/
	}
}