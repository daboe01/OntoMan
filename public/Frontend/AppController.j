@import <AppKit/AppKit.j>
@import <Foundation/CPObject.j>
@import <Renaissance/Renaissance.j>

@implementation AppController : CPObject
{
    CPTreeController treeController;
    CPOutlineView    outlineView;

    // UI Elements
    CPTextView       definitionTextView;
    CPTableView      synonymsTableView;
    CPTableView      xrefsTableView;
    CPTableView      downstreamTableView;

    // Search UI elements
    CPCheckBox       _nameOnlyCheckbox;
    CPTextField      _searchStatusLabel;
    CPTextField      _searchField;
    CPPopover        _exportPopover;

    // Phenopacket Extractor UI elements
    CPTextView       _reportInputTextView;
    CPTextView       _phenopacketOutputTextView;
    CPButton         _extractButton;

    // Data stores
    CPArray          _allRoots;
    CPArray          _synonyms;
    CPArray          _xrefs;
    CPArray          _downstreamTerms;

    // Search tracking
    CPArray          _matchedIndexPaths;
    int              _currentMatchIndex;

    // Phenopacket Extractor UI elements
    CPTextView       _reportInputTextView;
    CPTextView       _phenopacketOutputTextView;
    CPButton         _extractButton;
    CPTextField      _extractStatusLabel;
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    var theWindow = [[CPWindow alloc] initWithContentRect:CGRectMake(0, 0, 900, 700) styleMask:CPBorderlessBridgeWindowMask];
    [theWindow setTitle:@"Human Phenotype Ontology & Phenopacket Extractor"];
    [theWindow center];

    var contentView = [theWindow contentView];
    var bounds = [contentView bounds];

    // --- SETUP MAIN TAB VIEW ---
    var tabView = [[CPTabView alloc] initWithFrame:bounds];[tabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [contentView addSubview:tabView];

    // ==========================================
    // TAB 1: HPO Browser
    // ==========================================
    var tab1 = [[CPTabViewItem alloc] initWithIdentifier:@"tab1"];
    [tab1 setLabel:@"HPO Browser"];
    var tab1View = [[CPView alloc] initWithFrame:bounds];[tab1 setView:tab1View];
    [tabView addTabViewItem:tab1];

    // 1. Setup the Tree Controller
    treeController = [[CPTreeController alloc] init];[treeController setChildrenKeyPath:@"children"];
    [treeController setLeafKeyPath:@"isLeaf"];

    _synonyms = [];
    _xrefs = [];
    _downstreamTerms = [];
    _matchedIndexPaths = [];
    _currentMatchIndex = -1;

    // 2. Setup the Search Field & Controls (Top of Tab 1)
    var topWidth = CGRectGetWidth(bounds) - 40;
    var searchFieldWidth = topWidth - 270; // Reserve space for buttons/checkbox

    _searchField = [[CPSearchField alloc] initWithFrame:CGRectMake(20, 10, searchFieldWidth, 30)];
    [_searchField setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [_searchField setPlaceholderString:@"Search terms, synonyms, defs..."];
    [_searchField setTarget:self];
    [_searchField setAction:@selector(searchAction:)];
    [tab1View addSubview:_searchField];

    // Status Label ("1 of 5")
    _searchStatusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20 + searchFieldWidth + 10, 15, 60, 20)];
    [_searchStatusLabel setStringValue:@""];
    [_searchStatusLabel setAutoresizingMask:CPViewMinXMargin | CPViewMaxYMargin];
    [_searchStatusLabel setAlignment:CPRightTextAlignment];
    [tab1View addSubview:_searchStatusLabel];

    // Previous Button
    var prevBtn = [[CPButton alloc] initWithFrame:CGRectMake(20 + searchFieldWidth + 80, 13, 30, 24)];
    [prevBtn setTitle:@"<"];
    [prevBtn setAutoresizingMask:CPViewMinXMargin | CPViewMaxYMargin];
    [prevBtn setTarget:self];
    [prevBtn setAction:@selector(prevMatch:)];
    [tab1View addSubview:prevBtn];

    // Next Button
    var nextBtn = [[CPButton alloc] initWithFrame:CGRectMake(20 + searchFieldWidth + 115, 13, 30, 24)];
    [nextBtn setTitle:@">"];
    [nextBtn setAutoresizingMask:CPViewMinXMargin | CPViewMaxYMargin];
    [nextBtn setTarget:self];
    [nextBtn setAction:@selector(nextMatch:)];
    [tab1View addSubview:nextBtn];

    // Name Only Checkbox
    _nameOnlyCheckbox = [[CPCheckBox alloc] initWithFrame:CGRectMake(20 + searchFieldWidth + 155, 15, 100, 20)];
    [_nameOnlyCheckbox setTitle:@"Name only"];
    [_nameOnlyCheckbox setAutoresizingMask:CPViewMinXMargin | CPViewMaxYMargin];
    [_nameOnlyCheckbox setState:CPOffState]; // Default is OFF (searches all)
    [tab1View addSubview:_nameOnlyCheckbox];

    // 3. Setup Split View (Bottom Main Left/Right of Tab 1)
    // Reduce height slightly to account for the tab bar at the top
    var splitViewHeight = CGRectGetHeight(bounds) - 90;
    var splitView = [[CPSplitView alloc] initWithFrame:CGRectMake(20, 50, CGRectGetWidth(bounds) - 40, splitViewHeight)];
    [splitView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [splitView setVertical:YES]; // Left/Right split panes

    var splitBounds = [splitView bounds];
    var splitWidth = CGRectGetWidth(splitBounds);
    var splitHeight = CGRectGetHeight(splitBounds);
    var dividerWidth = [splitView dividerThickness];

    var leftWidth = (splitWidth - dividerWidth) * 0.60;
    var rightWidth = (splitWidth - dividerWidth) - leftWidth;

    // --- LEFT PANE: Outline View (60%) ---
    var leftScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, leftWidth, splitHeight)];
    [leftScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [leftScroll setAutohidesScrollers:NO];

    outlineView = [[CPOutlineView alloc] initWithFrame:[leftScroll bounds]];
    var column = [[CPTableColumn alloc] initWithIdentifier:@"name"];
    [[column headerView] setStringValue:@"HPO Terms"];

    [column setResizingMask:CPTableColumnAutoresizingMask];
    [outlineView setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];
    [outlineView addTableColumn:column];
    [outlineView setOutlineTableColumn:column];
    [outlineView setAllowsMultipleSelection:NO];
    [outlineView setDelegate:self];
    [leftScroll setDocumentView:outlineView];
    [splitView addSubview:leftScroll];

    // --- RIGHT PANE: Vertical Split View (40%) ---
    var rightSplitView = [[CPSplitView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight)];
    [rightSplitView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [rightSplitView setVertical:NO]; // Top/Bottom split panes

    // SECTION 3.0: Definition TextView
    var defScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight * 0.25)];
    [defScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [defScroll setAutohidesScrollers:YES];
    [defScroll setHasHorizontalScroller:NO];

    definitionTextView = [[CPTextView alloc] initWithFrame:[defScroll bounds]];
    [definitionTextView setAutoresizingMask:CPViewWidthSizable];
    [definitionTextView setEditable:NO];
    [definitionTextView setSelectable:YES];

    [defScroll setDocumentView:definitionTextView];

    var defBox = [[CPBox alloc] initWithFrame:CGRectMake(0,0, rightWidth, splitHeight * 0.25)];
    [defBox setTitle:@"Definition"];
    [defBox setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [[defBox contentView] addSubview:defScroll];
    [rightSplitView addSubview:defBox];

    // SECTION 3.1: Xrefs TableView
    var xrefScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight * 0.20)];
    [xrefScroll setAutohidesScrollers:YES];

    xrefsTableView = [[CPTableView alloc] initWithFrame:[xrefScroll bounds]];
    var xrefCol = [[CPTableColumn alloc] initWithIdentifier:@"xref"];
    [xrefCol setSortDescriptorPrototype:[CPSortDescriptor sortDescriptorWithKey:@"xref" ascending:YES]];
    [[xrefCol headerView] setStringValue:@"Cross References"];
    [xrefCol setWidth:rightWidth - 5];
    [xrefsTableView addTableColumn:xrefCol];
    [xrefsTableView setDataSource:self];
    [xrefScroll setDocumentView:xrefsTableView];
    [xrefScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    var xrefBox = [[CPBox alloc] initWithFrame:CGRectMake(0,0, rightWidth, splitHeight * 0.20)];
    [xrefBox setTitle:@"Cross References (Xrefs)"];
    [xrefBox setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [[xrefBox contentView] addSubview:xrefScroll];
    [rightSplitView addSubview:xrefBox];

    // SECTION 3.2: Synonyms TableView
    var synScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight * 0.25)];
    [synScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [synScroll setAutohidesScrollers:YES];

    synonymsTableView = [[CPTableView alloc] initWithFrame:[synScroll bounds]];
    var synCol = [[CPTableColumn alloc] initWithIdentifier:@"label"];
    [[synCol headerView] setStringValue:@"Synonyms"];
    [synCol setSortDescriptorPrototype:[CPSortDescriptor sortDescriptorWithKey:@"label" ascending:YES]];
    [synCol setWidth:rightWidth - 5];
    [synonymsTableView addTableColumn:synCol];
    [synonymsTableView setDataSource:self];
    [synScroll setDocumentView:synonymsTableView];
    [rightSplitView addSubview:synScroll];

    // SECTION 3.3: Downstream Codes TableView
    var textBox = [[CPBox alloc] initWithFrame:CGRectMake(0,0, rightWidth, splitHeight * 0.30)];
    [textBox setTitle:@"Downstream Nodes"];[textBox setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    var contentBounds = [[textBox contentView] bounds];

    var downScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(contentBounds), CGRectGetHeight(contentBounds) - 34)];
    [downScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [downScroll setAutohidesScrollers:YES];

    downstreamTableView = [[CPTableView alloc] initWithFrame:[downScroll bounds]];
    [downstreamTableView setTarget:self];
    [downstreamTableView setDoubleAction:@selector(doubleClickDownstream:)];

    var downIdCol = [[CPTableColumn alloc] initWithIdentifier:@"id"];
    [[downIdCol headerView] setStringValue:@"ID"];
    [downIdCol setSortDescriptorPrototype:[CPSortDescriptor sortDescriptorWithKey:@"id" ascending:YES]];
    [downIdCol setWidth:80];
    [downstreamTableView addTableColumn:downIdCol];

    var downLabelCol = [[CPTableColumn alloc] initWithIdentifier:@"label"];
    [[downLabelCol headerView] setStringValue:@"Label"];
    [downLabelCol setSortDescriptorPrototype:[CPSortDescriptor sortDescriptorWithKey:@"label" ascending:YES]];
    [downLabelCol setWidth:rightWidth - 88];
    [downstreamTableView addTableColumn:downLabelCol];
    [downstreamTableView setDataSource:self];
    [downScroll setDocumentView:downstreamTableView];
    [[textBox contentView] addSubview:downScroll];

    // Export IDs Button
    var exportBtn = [[CPButton alloc] initWithFrame:CGRectMake(3, CGRectGetMaxY([downScroll bounds]) + 3, 120, 24)];
    [exportBtn setAutoresizingMask:CPViewMinYMargin | CPViewMaxXMargin];
    [exportBtn setTitle:@"Export IDs"];
    [exportBtn setTarget:self];
    [exportBtn setAction:@selector(exportDownstream:)];
    [[textBox contentView] addSubview:exportBtn];
    [rightSplitView addSubview:textBox];
    [splitView addSubview:rightSplitView];
    [tab1View addSubview:splitView];

    // 4. Establish Bindings
    [outlineView bind:@"content" toObject:treeController withKeyPath:@"arrangedObjects" options:nil];
    [outlineView bind:@"selectionIndexPaths" toObject:treeController withKeyPath:@"selectionIndexPaths" options:nil];


    // ==========================================
    // TAB 2: Phenopacket Extractor
    // ==========================================
    var tab2 = [[CPTabViewItem alloc] initWithIdentifier:@"tab2"];
    [tab2 setLabel:@"Phenopacket Extractor"];
    var tab2View = [[CPView alloc] initWithFrame:bounds];
    [tab2 setView:tab2View];
    [tabView addTabViewItem:tab2];

    var tab2Bounds =[tab2View bounds];

    // Extractor Split View (Left: Input, Right: Output)
    var extractorSplitHeight = CGRectGetHeight(tab2Bounds) - 90;
    var extractorSplit = [[CPSplitView alloc] initWithFrame:CGRectMake(20, 20, CGRectGetWidth(tab2Bounds) - 40, extractorSplitHeight)];
    [extractorSplit setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];[extractorSplit setVertical:YES]; // Left/Right panes

    var extractorWidth = CGRectGetWidth([extractorSplit bounds]);
    var extractorDivider = [extractorSplit dividerThickness];
    var halfWidth = (extractorWidth - extractorDivider) / 2;

    // --- Extractor Left: Input ---
    var inputBox = [[CPBox alloc] initWithFrame:CGRectMake(0, 0, halfWidth, extractorSplitHeight)];
    [inputBox setTitle:@"Narrative Medical Report"];
    [inputBox setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    var inputScroll2 = [[CPScrollView alloc] initWithFrame:[[inputBox contentView] bounds]];
    [inputScroll2 setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];[inputScroll2 setAutohidesScrollers:YES];

    _reportInputTextView = [[CPTextView alloc] initWithFrame:[inputScroll2 bounds]];
    [_reportInputTextView setAutoresizingMask:CPViewWidthSizable];
    [inputScroll2 setDocumentView:_reportInputTextView];

    [[inputBox contentView] addSubview:inputScroll2];
    [extractorSplit addSubview:inputBox];

    // --- Extractor Right: Output ---
    var outputBox = [[CPBox alloc] initWithFrame:CGRectMake(0, 0, halfWidth, extractorSplitHeight)];
    [outputBox setTitle:@"Extracted Phenopacket (JSON)"];
    [outputBox setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    var outputScroll2 = [[CPScrollView alloc] initWithFrame:[[outputBox contentView] bounds]];
    [outputScroll2 setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [outputScroll2 setAutohidesScrollers:YES];

    _phenopacketOutputTextView = [[CPTextView alloc] initWithFrame:[outputScroll2 bounds]];
    [_phenopacketOutputTextView setAutoresizingMask:CPViewWidthSizable];
    [_phenopacketOutputTextView setEditable:NO];
    [_phenopacketOutputTextView setSelectable:YES];
    [outputScroll2 setDocumentView:_phenopacketOutputTextView];

    [[outputBox contentView] addSubview:outputScroll2];
    [extractorSplit addSubview:outputBox];

    [tab2View addSubview:extractorSplit];

    // --- Extract Button ---
    _extractButton = [[CPButton alloc] initWithFrame:CGRectMake(20, CGRectGetMaxY([extractorSplit frame]) + 15, 180, 30)];
    [_extractButton setTitle:@"Extract phenopacket"];
    [_extractButton setAutoresizingMask:CPViewMinYMargin | CPViewMaxXMargin];
    [_extractButton setTarget:self];
    [_extractButton setAction:@selector(extractPhenopacketAction:)];
    [tab2View addSubview:_extractButton];

    _extractStatusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(CGRectGetMaxX([_extractButton frame]) + 20, CGRectGetMinY([_extractButton frame]) + 5 , 200, 20)];
    [_extractStatusLabel setStringValue:@""];
    [_extractStatusLabel setAutoresizingMask:CPViewMaxXMargin | CPViewMinYMargin];
    [_extractStatusLabel setAlignment:CPLeftTextAlignment];
    [tab2View addSubview:_extractStatusLabel];


    // 5. Finalize setup & load the roots
    [theWindow orderFront:self];
    [self fetchRoots];
}

// --- Phenopacket Extraction Action ---
// --- Phenopacket Extraction Action ---
- (void)extractPhenopacketAction:(id)sender
{
    var narrativeText = [_reportInputTextView string];

    if (!narrativeText || [narrativeText length] === 0) {
        [_phenopacketOutputTextView setString:@"Please paste a medical report on the left before extracting."];
        return;
    }

    [_extractButton setEnabled:NO];
    [_extractButton setTitle:@"Extracting..."];
    [_phenopacketOutputTextView setString:@"Extracting phenopacket, please wait..."];

    // Start animation

    var request = [CPURLRequest requestWithURL:"/DBB/extract_phenopacket"];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    var payload = { "report": narrativeText };
    var postData = [CPString stringWithString:JSON.stringify(payload)];
    [request setHTTPBody:postData];
    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error)
    {

        [_extractButton setEnabled:YES];
        [_extractButton setTitle:@"Extract phenopacket"];

        // Stop animation[self stopExtractPulsatingAnimation];
        [_extractStatusLabel setStringValue:@""];

        if (!error && data) {
            try {
                var parsedData = JSON.parse(data);
                var prettyJSON = JSON.stringify(parsedData, null, 4);
                [_phenopacketOutputTextView setString:prettyJSON];
            } catch (e) {
                [_phenopacketOutputTextView setString:data];
            }
        } else {
            var errorMsg = (error) ? [error localizedDescription] : @"Unknown error occurred.";
            [_phenopacketOutputTextView setString:@"Failed to extract phenopacket:\n\n" + errorMsg];
            CPLog("Extraction Error: %@", error);
        }
    }];
}

- (void)tableView:(CPTableView)tableView sortDescriptorsDidChange:(CPArray)oldDescriptors
{
    // 1. Identify which array we are sorting
    var arrayToSort = nil;
    if (tableView === synonymsTableView) {
        arrayToSort = _synonyms;
    } else if (tableView === xrefsTableView) {
        arrayToSort = _xrefs;
    } else if (tableView === downstreamTableView) {
        arrayToSort = _downstreamTerms;
    }

    if (!arrayToSort || [arrayToSort count] === 0)
        return;

    var descriptors = [tableView sortDescriptors];
    var mainDescriptor = [descriptors objectAtIndex:0];
    var key = [mainDescriptor key]; // e.g., "label" or "termId"
    var ascending = [mainDescriptor ascending];

    arrayToSort.sort(function(a, b) {
        var valA = a[key];
        var valB = b[key];

        if (valA === undefined) valA = "";
        if (valB === undefined) valB = "";

        if (valA < valB) return ascending ? -1 : 1;
        if (valA > valB) return ascending ? 1 : -1;
        return 0;
    });

    [tableView reloadData];
}

// --- TableView Data Source ---
- (int)numberOfRowsInTableView:(CPTableView)tableView
{
    if (tableView === synonymsTableView) {
        return [_synonyms count];
    }
    if (tableView === xrefsTableView) {
        return [_xrefs count];
    }
    if (tableView === downstreamTableView) {
        return [_downstreamTerms count];
    }
    return 0;
}

- (id)tableView:(CPTableView)tableView objectValueForTableColumn:(CPTableColumn)tableColumn row:(int)row
{
    if (tableView === synonymsTableView) {
        return _synonyms[row].label;
    }

    if (tableView === xrefsTableView) {
        return _xrefs[row].label;
    }

    if (tableView === downstreamTableView) {
        var term = _downstreamTerms[row];
        if ([tableColumn identifier] === @"id") {
            return term.id;
        } else if ([tableColumn identifier] === @"label") {
            return term.label;
        }
    }

    return nil;
}

- (void)fetchRoots
{
    var request = [CPURLRequest requestWithURL:"/DBB/hpo/roots"];
    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error) {
        if (!error && data) {
            var json = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil];
            var roots = [CPMutableArray array];
            for (var i = 0; i < json.length; i++) {
                var node = [[HPONode alloc] initWithDict:json[i]];
                [roots addObject:node];
            }

            _allRoots = roots;
            [treeController setContent:_allRoots];
        } else {
            CPLog("Failed to fetch HPO roots: %@", error);
        }
    }];
}

// --- Search Cycle Controls ---
- (void)prevMatch:(id)sender
{
    if (!_matchedIndexPaths || _matchedIndexPaths.length === 0)
        return;

    _currentMatchIndex--;

    if (_currentMatchIndex < 0)
        _currentMatchIndex = _matchedIndexPaths.length - 1;

    [self updateSelectionToCurrentMatch];
}

- (void)nextMatch:(id)sender
{
    if (!_matchedIndexPaths || _matchedIndexPaths.length === 0)
        return;

    _currentMatchIndex++;

    if (_currentMatchIndex >= _matchedIndexPaths.length)
        _currentMatchIndex = 0;

    [self updateSelectionToCurrentMatch];
}

- (void)setSearchStringResultValue:(CPString)val
{
    [self stopPulsatingAnimation];
    [_searchStatusLabel setStringValue:val];
}


- (void)setSearchAlphaValue:(float)val
{
    [_searchStatusLabel setAlphaValue:val];
}

- (void)animationDidStop:(CAAnimation)anim finished:(BOOL)finished
{
    if (!finished)
        return;

    var animId = anim._animationID;

    if (animId === @"searchPulse") {
        var currentOpacity =[_searchStatusLabel alphaValue];
        [self startPulsatingAnimationWithDirection:(currentOpacity < 0.15 ? 0 : 1)];
    }
    else if (animId === @"extractPulse") {
        var currentOpacity = [_extractStatusLabel alphaValue];
        [self startExtractPulsatingAnimationWithDirection:(currentOpacity < 0.15 ? 0 : 1)];
    }
    else {
        // Fallback
        var currentOpacity = [_searchStatusLabel alphaValue];
        [self startPulsatingAnimationWithDirection:(currentOpacity < 0.15 ? 0 : 1)];
    }
}

// --- Search Animation ---
- (void)startPulsatingAnimation
{
    [self startPulsatingAnimationWithDirection:0];
}

- (void)startPulsatingAnimationWithDirection:(int)direction
{
    var fromValue = (direction == 0) ? 0.0 : 0.8;
    var toValue   = (direction == 0) ? 0.8 : 0.0;

    [_searchStatusLabel setWantsLayer:YES];
    var layer = [_searchStatusLabel layer];
    [layer setDelegate:self];

    var pulseAnimation = [CABasicAnimation animationWithKeyPath:@"searchAlphaValue"];
    pulseAnimation._animationID = "searchPulse";
    [pulseAnimation setDelegate:self];
    [pulseAnimation setFromValue:fromValue];
    [pulseAnimation setToValue:toValue];
    [pulseAnimation setDuration:0.6];
    [layer addAnimation:pulseAnimation forKey:@"searchAlphaValue"];
}

- (void)stopPulsatingAnimation
{
    [[_searchStatusLabel layer] removeAnimationForKey:@"searchAlphaValue"];[self setSearchAlphaValue:1.0];
}

// --- Extract Animation ---
- (void)setExtractAlphaValue:(float)val
{
    [_extractStatusLabel setAlphaValue:val];
}

- (void)startExtractPulsatingAnimation
{
    [self startExtractPulsatingAnimationWithDirection:0];
}

- (void)startExtractPulsatingAnimationWithDirection:(int)direction
{
    var fromValue = (direction == 0) ? 0.0 : 0.8;
    var toValue   = (direction == 0) ? 0.8 : 0.0;
    [_extractStatusLabel setWantsLayer:YES];
    var layer = [_extractStatusLabel layer];
    [layer setDelegate:self];

    var pulseAnimation = [CABasicAnimation animationWithKeyPath:@"extractAlphaValue"];
    pulseAnimation._animationID = "extractPulse";
    [pulseAnimation setDelegate:self];
    [pulseAnimation setFromValue:fromValue];
    [pulseAnimation setToValue:toValue];
    [pulseAnimation setDuration:0.6];
    [layer addAnimation:pulseAnimation forKey:@"extractAlphaValue"];
}

- (void)stopExtractPulsatingAnimation
{
    [[_extractStatusLabel layer] removeAnimationForKey:@"extractAlphaValue"];
    [self setExtractAlphaValue:1.0];
}

// --- Delegate Method: Triggers when the user selects a row ---
- (void)outlineViewSelectionDidChange:(CPNotification)notification
{
    var selectedRow = [outlineView selectedRow];

    if (selectedRow === -1) {
        _synonyms = [];
        _xrefs = [];
        _downstreamTerms = [];
        [definitionTextView setString:@""];

        [synonymsTableView reloadData];
        [xrefsTableView reloadData];
        [downstreamTableView reloadData];

        return;
    }

    var item = [outlineView itemAtRow:selectedRow];
    var node = [item representedObject];

    [definitionTextView setString:[node definition] + ' (HP:' +[CPString stringWithFormat:"%07d", node.termId + 0] + ')' || @"No definition available."];
    [self fetchDownstreamForNode:node];
    [self fetchSynonymsForNode:node];
    [self fetchXrefsForNode:node];
}

- (void)fetchDownstreamForNode:(HPONode)node
{
    var urlString = "/DBB/children/idparent/" + [node termId];
    var request = [CPURLRequest requestWithURL:urlString];
    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error)
    {
        if (!error && data) {
            _downstreamTerms = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil] ||[];
        }
        else {
            _downstreamTerms = [];
        }
        [downstreamTableView reloadData];
    }];
}

// --- Trigger Search ---
- (void)searchAction:(id)sender
{
    var searchString = [sender stringValue];
    var isNameOnly = [_nameOnlyCheckbox state] === CPOnState;
    [self performSearchForString:searchString isNameOnly:isNameOnly];
}

- (void)performSearchForString:(CPString)searchString isNameOnly:(BOOL)isNameOnly
{
    if (!searchString || [searchString length] === 0)
    {
        [treeController setSelectionIndexPaths:[]];
        _matchedIndexPaths = [];
        _currentMatchIndex = -1;[_searchStatusLabel setStringValue:@""];

        return;
    }

    CPLog("Suche läuft nach: " + searchString);
    [_searchStatusLabel setStringValue:@"Searching..."];
    [self startPulsatingAnimation];

    var urlString = "/DBB/hpo/search/" + encodeURIComponent(searchString) + "?nameOnly=" + (isNameOnly ? "1" : "0");
    var request = [CPURLRequest requestWithURL:urlString];

    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error)
     {
        if (!error && data)
        {
            var json =[CPJSONSerialization JSONObjectWithData:data options:0 error:nil];
            [self expandAndSelectPaths:json];
        }
        else
        {
            CPLog("Fehler bei der Suche.");
            [_searchStatusLabel setStringValue:@"Error"];
        }
    }];
}

// --- Downstream Features ---
- (void)doubleClickDownstream:(id)sender
{
    var clickedRow = [downstreamTableView clickedRow];
    if (clickedRow < 0 || clickedRow >= _downstreamTerms.length) return;

    var term = _downstreamTerms[clickedRow];
    var formattedId = "HP:" +[CPString stringWithFormat:"%07d", term.id + 0];

    [_searchField setStringValue:formattedId];
    [_nameOnlyCheckbox setState:CPOffState];
    [self performSearchForString:formattedId isNameOnly:NO];
}

- (void)exportDownstream:(id)sender
{
    if (!_downstreamTerms || _downstreamTerms.length === 0)
        return;

    var textToExport = "";

    for (var i = 0; i < _downstreamTerms.length; i++) {
        var termId = _downstreamTerms[i].id;
        var formatted = "HP:" +[CPString stringWithFormat:"%07d", termId + 0];
        textToExport += formatted + "\n";
    }

    if (!_exportPopover)
    {
        _exportPopover = [CPPopover new];
        [_exportPopover setBehavior:CPPopoverBehaviorTransient];
        [_exportPopover setAppearance:CPPopoverAppearanceMinimal];
        [_exportPopover setAnimates:YES];

        var containerView = [[CPView alloc] initWithFrame:CGRectMake(0, 0, 250, 350)];

        var scrollView = [[CPScrollView alloc] initWithFrame:[containerView bounds]];
        [scrollView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [scrollView setAutohidesScrollers:YES];

        _exportTextView = [[CPTextView alloc] initWithFrame:[scrollView bounds]];
        [_exportTextView setAutoresizingMask:CPViewWidthSizable];
        [_exportTextView setEditable:NO];
        [_exportTextView setSelectable:YES];

        [scrollView setDocumentView:_exportTextView];
        [containerView addSubview:scrollView];

        var myViewController = [CPViewController new];
        [myViewController setView:containerView];
        [_exportPopover setContentViewController:myViewController];
    }

    [_exportTextView setString:textToExport];
    [_exportPopover showRelativeToRect:[sender bounds] ofView:sender preferredEdge:CPMinYEdge];

    window.setTimeout(function() {
        [_exportTextView selectAll:self];
    }, 50);
}

- (void)fetchSynonymsForNode:(HPONode)node
{
    var urlString = "/DBB/hpo/synonyms/" + [node termId];
    var request = [CPURLRequest requestWithURL:urlString];
    [CPURLConnection sendAsynchronousRequest:request queue:[CPOperationQueue mainQueue] completionHandler:function(response, data, error) {
        if (!error && data) {
            _synonyms = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil] ||[];
        } else {
            _synonyms = [];
        }
        [synonymsTableView reloadData];
    }];
}

- (void)fetchXrefsForNode:(HPONode)node
{
    var urlString = "/DBB/hpo/xrefs/" + [node termId];
    var request = [CPURLRequest requestWithURL:urlString];

    [CPURLConnection sendAsynchronousRequest:request queue:[CPOperationQueue mainQueue] completionHandler:function(response, data, error) {
        if (!error && data) {
            _xrefs = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil] || [];
        } else {
            _xrefs = [];
        }[xrefsTableView reloadData];
    }];
}

// --- 1. Helper method to properly build CPTreeNode proxies ---
- (void)syncTreeNode:(CPTreeNode)treeNode withModelChildren:(CPArray)newChildren
{
    if (!treeNode)
        return;

    var mutableChildNodes = [treeNode mutableChildNodes];

    if ([mutableChildNodes count] > 0)
    {
        var firstChildObj = [[mutableChildNodes objectAtIndex:0] representedObject];
        if ([firstChildObj name] !== @"Loading...") {
            return;
        }
    } else if ([mutableChildNodes count] === 0 && [newChildren count] === 0) {
        return;
    }

    [mutableChildNodes removeAllObjects];

    for (var i = 0; i < [newChildren count]; i++) {
        var childModel = newChildren[i];
        var childTreeNode = [[CPTreeNode alloc] initWithRepresentedObject:childModel];

        if (![childModel isLeaf] && [[childModel children] count] > 0) {
            var dummyModel = [[childModel children] objectAtIndex:0];
            var dummyTreeNode = [[CPTreeNode alloc] initWithRepresentedObject:dummyModel];
            [[childTreeNode mutableChildNodes] addObject:dummyTreeNode];
        }

        [mutableChildNodes addObject:childTreeNode];
    }
}

// --- 2. Fixed shouldExpandItem ---
- (BOOL)outlineView:(CPOutlineView)anOutlineView shouldExpandItem:(id)anItem
{
    var node = [anItem representedObject];

    if (!node || [node isLeaf]) return YES;

    if ([node hasLoadedChildren]) {
        [self syncTreeNode:anItem withModelChildren:[node children]];
        return YES;
    }

    var expandStartTime = [CPDate timeIntervalSinceReferenceDate];
    [node fetchChildrenWithCompletion:function(newChildren) {

        var elapsed = [CPDate timeIntervalSinceReferenceDate] - expandStartTime;
        var animationDuration = 0.25;
        var delay = MAX(0, animationDuration - elapsed + 0.05);

        setTimeout(function() {
            [self syncTreeNode:anItem withModelChildren:newChildren];[anOutlineView reloadItem:anItem reloadChildren:YES];

        }, delay * 1000);
    }];

    return YES;
}

- (void)resolvePath:(CPArray)nodeIds currentIndex:(int)index currentModels:(CPArray)models baseIndexPath:(CPIndexPath)indexPath completion:(Function)callback
{
    if (index >= nodeIds.length) {
        callback(indexPath);
        return;
    }

    var targetId = parseInt(nodeIds[index], 10);
    var foundModelIndex = -1;
    var foundModel = nil;

    for (var i = 0; i < [models count]; i++) {
        if ([models[i] termId] === targetId) {
            foundModelIndex = i;
            foundModel = models[i];
            break;
        }
    }

    if (!foundModel) {
        callback(nil);
        return;
    }

    var nextIndexPath = indexPath ? [indexPath indexPathByAddingIndex:foundModelIndex] : [CPIndexPath indexPathWithIndex:foundModelIndex];

    if (index === nodeIds.length - 1) {
        callback(nextIndexPath);
    } else {
        [foundModel fetchChildrenWithCompletion:function(newChildren) {

            var treeNode = [[treeController arrangedObjects] descendantNodeAtIndexPath:nextIndexPath];
            if (treeNode) {
                [self syncTreeNode:treeNode withModelChildren:newChildren];
            }

            [self resolvePath:nodeIds currentIndex:(index + 1) currentModels:newChildren baseIndexPath:nextIndexPath completion:callback];
        }];
    }
}

// --- 4. Fixed Search Selection UI ---
- (void)updateSelectionToCurrentMatch
{
    if (!_matchedIndexPaths || [_matchedIndexPaths count] === 0)
    {
        [self setSearchStringResultValue:@"0 hits"];

        return;
    }

    var path = _matchedIndexPaths[_currentMatchIndex];
    var partialPath = [CPIndexPath indexPathWithIndex:[path indexAtPosition:0]];

    for (var level = 1; level < [path length]; level++)
    {
        var treeNode = [[treeController arrangedObjects] descendantNodeAtIndexPath:partialPath];

        if (treeNode)
            [outlineView expandItem:treeNode];

        partialPath = [partialPath indexPathByAddingIndex:[path indexAtPosition:level]];
    }

    [treeController setSelectionIndexPath:path];
    [self setSearchStringResultValue:(_currentMatchIndex + 1) + @" of " + [_matchedIndexPaths count]];

    setTimeout(function() {
        var node = [[treeController arrangedObjects] descendantNodeAtIndexPath:path];
        if (node) {
            var rowIndex = [outlineView rowForItem:node];
            if (rowIndex >= 0) {
                [outlineView scrollRowToVisible:rowIndex];
            } else {
                CPLog.warn("Target row index is -1. Layout incomplete for path: " + [path description]);
            }
        }
    }, 300);
}

- (void)expandAndSelectPaths:(CPArray)searchResults
{
    if (!searchResults || searchResults.length === 0)
    {
        CPLog("Keine Treffer gefunden.");
        [treeController setSelectionIndexPaths:[]];
        _matchedIndexPaths = [];
        _currentMatchIndex = -1;
        [self setSearchStringResultValue:@"0 hits"];

        return;
    }

    CPLog(searchResults.length + " Treffer gefunden. Lade Baumstruktur...");

    var targetIndexPaths = [CPMutableArray array];
    var pendingPaths = searchResults.length;

    for (var i = 0; i < searchResults.length; i++)
    {
        var nodeIds = searchResults[i].path;
        [self resolvePath:nodeIds
             currentIndex:0
            currentModels:_allRoots
            baseIndexPath:nil
               completion:function(finalIndexPath) {

            if (finalIndexPath)
            {
                [targetIndexPaths addObject:finalIndexPath];
            }

            pendingPaths--;

            if (pendingPaths === 0)
            {
                _matchedIndexPaths = targetIndexPaths;
                _currentMatchIndex = 0;

                setTimeout(function() {
                    [self updateSelectionToCurrentMatch];
                }, 50);

                CPLog("Alle Treffer aufgelöst und der erste wurde markiert.");
            }
        }];
    }
}

@end

// --- Custom Data Model representing a single HPO Node ---
@implementation HPONode : CPObject
{
    int      termId            @accessors(property=termId);
    CPString name              @accessors(property=name);
    CPString definition        @accessors(property=definition);
    BOOL     isLeaf            @accessors(property=isLeaf);
    CPArray  children;
    BOOL     hasLoadedChildren @accessors(property=hasLoadedChildren);
    BOOL     _isFetching;
    CPArray  _fetchCallbacks;
}

- (id)initWithDict:(JSObject)dict
{
    self = [super init];

    if (self)
    {
        termId = dict.id;
        name = dict.label;
        definition = dict.definition || dict.label;

        isLeaf = (dict.is_leaf == 1);

        if (!isLeaf)
        {
            var dummyNode = [[HPONode alloc] initAsDummy];
            children = [dummyNode];
        }
        else
        {
            children = [];
        }

        hasLoadedChildren = NO;
    }

    return self;
}

- (id)initAsDummy
{
    self = [super init];

    if (self)
    {
        name = @"Loading...";
        definition = @"";
        isLeaf = YES;
        children = [];
        hasLoadedChildren = YES;
    }
    return self;
}

- (void)setChildren:(CPArray)someChildren
{
    [self willChangeValueForKey:@"children"];
    children = someChildren;
    [self didChangeValueForKey:@"children"];
}

- (CPArray)children
{
    return children;
}

- (void)fetchChildrenWithCompletion:(Function)completion
{
    if (hasLoadedChildren) {
        if (completion) completion(children);
        return;
    }

    if (!_fetchCallbacks)
    {
        _fetchCallbacks = [];
    }

    if (completion)
        [_fetchCallbacks addObject:completion];

    if (_isFetching)
        return;

    _isFetching = YES;

    var urlString = "/DBB/hpo/children/" + termId;
    var request = [CPURLRequest requestWithURL:urlString];

    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error) {
        _isFetching = NO;

        if (!error && data)
        {
            var json = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil];
            var newChildren = [CPMutableArray array];

            for (var i = 0; i < json.length; i++) {
                var childNode = [[HPONode alloc] initWithDict:json[i]];
                [newChildren addObject:childNode];
            }

            hasLoadedChildren = YES;
            [self setChildren:newChildren];

            var callbacksToRun = [_fetchCallbacks copy];
            [_fetchCallbacks removeAllObjects];
            for (var i = 0; i < callbacksToRun.length; i++) {
                callbacksToRun[i](newChildren);
            }
        } else {
            CPLog("Failed to load children for term id %@: %@", termId, error);
            var callbacksToRun = [_fetchCallbacks copy];
            [_fetchCallbacks removeAllObjects];
            for (var i = 0; i < callbacksToRun.length; i++) {
                callbacksToRun[i]([]);
            }
        }
    }];
}

@end

@implementation CPJSONSerialization : CPObject

+ (id)JSONObjectWithData:(CPString)data options:(int)options error:(id)error
{
    if (!data || [data length] === 0) {
        return nil;
    }

    try {
        return JSON.parse(data);
    }
    catch (e) {
        CPLog.error(@"CPJSONSerialization Error parsing JSON: " + e.message);
        return nil;
    }
}

+ (CPString)dataWithJSONObject:(id)object options:(int)options error:(id)error
{
    if (!object) {
        return nil;
    }

    try {
        return JSON.stringify(object);
    }
    catch (e) {
        CPLog.error(@"CPJSONSerialization Error stringifying object: " + e.message);
        return nil;
    }
}

+ (BOOL)isValidJSONObject:(id)object
{
    if (!object) {
        return NO;
    }

    try {
        JSON.stringify(object);
        return YES;
    }
    catch (e) {
        return NO;
    }
}

@end
