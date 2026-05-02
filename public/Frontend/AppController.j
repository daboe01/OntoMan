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
    
    // Data stores
    CPArray          _allRoots;
    CPArray          _synonyms;
    CPArray          _xrefs;
    CPArray          _downstreamTerms;
    
    // Search tracking
    CPArray          _matchedIndexPaths;
    int              _currentMatchIndex;
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    var theWindow = [[CPWindow alloc] initWithContentRect:CGRectMake(0, 0, 800, 600) styleMask:CPBorderlessBridgeWindowMask];
    [theWindow setTitle:@"Human Phenotype Ontology"];
    [theWindow center];

    var contentView = [theWindow contentView];
    var bounds = [contentView bounds];

    // 1. Setup the Tree Controller
    treeController = [[CPTreeController alloc] init];
    [treeController setChildrenKeyPath:@"children"];
    [treeController setLeafKeyPath:@"isLeaf"];

    _synonyms = [];
    _xrefs = [];
    _downstreamTerms = [];
    _matchedIndexPaths = [];
    _currentMatchIndex = -1;

    // 2. Setup the Search Field & Controls (Top)
    var topWidth = CGRectGetWidth(bounds) - 40;
    var searchFieldWidth = topWidth - 270; // Reserve space for buttons/checkbox

    var searchField = [[CPSearchField alloc] initWithFrame:CGRectMake(20, 10, searchFieldWidth, 30)];
    [searchField setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [searchField setPlaceholderString:@"Search terms, synonyms, defs..."];
    [searchField setTarget:self];
    [searchField setAction:@selector(searchAction:)];
    [contentView addSubview:searchField];

    // Status Label ("1 of 5")
    _searchStatusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20 + searchFieldWidth + 10, 15, 60, 20)];
    [_searchStatusLabel setStringValue:@""];
    [_searchStatusLabel setAutoresizingMask:CPViewMinXMargin | CPViewMaxYMargin];
    [_searchStatusLabel setAlignment:CPRightTextAlignment];
    [contentView addSubview:_searchStatusLabel];

    // Previous Button
    var prevBtn = [[CPButton alloc] initWithFrame:CGRectMake(20 + searchFieldWidth + 80, 13, 30, 24)];
    [prevBtn setTitle:@"<"];
    [prevBtn setAutoresizingMask:CPViewMinXMargin | CPViewMaxYMargin];
    [prevBtn setTarget:self];
    [prevBtn setAction:@selector(prevMatch:)];
    [contentView addSubview:prevBtn];

    // Next Button
    var nextBtn = [[CPButton alloc] initWithFrame:CGRectMake(20 + searchFieldWidth + 115, 13, 30, 24)];
    [nextBtn setTitle:@">"];
    [nextBtn setAutoresizingMask:CPViewMinXMargin | CPViewMaxYMargin];
    [nextBtn setTarget:self];
    [nextBtn setAction:@selector(nextMatch:)];
    [contentView addSubview:nextBtn];

    // Name Only Checkbox
    _nameOnlyCheckbox = [[CPCheckBox alloc] initWithFrame:CGRectMake(20 + searchFieldWidth + 155, 15, 100, 20)];
    [_nameOnlyCheckbox setTitle:@"Name only"];
    [_nameOnlyCheckbox setAutoresizingMask:CPViewMinXMargin | CPViewMaxYMargin];
    [_nameOnlyCheckbox setState:CPOffState]; // Default is OFF (searches all)
    [contentView addSubview:_nameOnlyCheckbox];

    // 3. Setup Split View (Bottom Main Left/Right)
    var splitView = [[CPSplitView alloc] initWithFrame:CGRectMake(20, 50, CGRectGetWidth(bounds) - 40, CGRectGetHeight(bounds) - 70)];
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
    var synCol = [[CPTableColumn alloc] initWithIdentifier:@"synonym"];
    [[synCol headerView] setStringValue:@"Synonyms"];
    [synCol setWidth:rightWidth - 5];
    [synonymsTableView addTableColumn:synCol];
    [synonymsTableView setDataSource:self];
    [synScroll setDocumentView:synonymsTableView];
    [rightSplitView addSubview:synScroll];

    // SECTION 3.3: Downstream Codes TableView
    var downScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight * 0.30)];
    [downScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [downScroll setAutohidesScrollers:YES];

    downstreamTableView = [[CPTableView alloc] initWithFrame:[downScroll bounds]];
    
    var downIdCol = [[CPTableColumn alloc] initWithIdentifier:@"id"];
    [[downIdCol headerView] setStringValue:@"ID"];
    [downIdCol setWidth:80];
    [downstreamTableView addTableColumn:downIdCol];

    var downLabelCol = [[CPTableColumn alloc] initWithIdentifier:@"label"];
    [[downLabelCol headerView] setStringValue:@"Label"];
    [downLabelCol setWidth:rightWidth - 85];
    [downstreamTableView addTableColumn:downLabelCol];

    [downstreamTableView setDataSource:self];
    [downScroll setDocumentView:downstreamTableView];

    var textBox = [[CPBox alloc] initWithFrame:CGRectMake(0,0, rightWidth, splitHeight * 0.30)];
    [textBox setTitle:@"Downstream Nodes"];
    [textBox setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [[textBox contentView] addSubview:downScroll];

    [rightSplitView addSubview:textBox];

    [splitView addSubview:rightSplitView];
    [contentView addSubview:splitView];

    // 4. Establish Bindings
    [outlineView bind:@"content" toObject:treeController withKeyPath:@"arrangedObjects" options:nil];
    [outlineView bind:@"selectionIndexPaths" toObject:treeController withKeyPath:@"selectionIndexPaths" options:nil];

    [theWindow orderFront:self];

    // 5. Kick off loading the root nodes
    [self fetchRoots];
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
            
            _allRoots = roots; // Store a master copy for filtering
            [treeController setContent:_allRoots];
        } else {
            CPLog("Failed to fetch HPO roots: %@", error);
        }
    }];
}

// --- Search Cycle Controls ---
- (void)prevMatch:(id)sender
{
    if (!_matchedIndexPaths || _matchedIndexPaths.length === 0) return;
    _currentMatchIndex--;
    if (_currentMatchIndex < 0) _currentMatchIndex = _matchedIndexPaths.length - 1;
    [self updateSelectionToCurrentMatch];
}

- (void)nextMatch:(id)sender
{
    if (!_matchedIndexPaths || _matchedIndexPaths.length === 0) return;
    _currentMatchIndex++;
    if (_currentMatchIndex >= _matchedIndexPaths.length) _currentMatchIndex = 0;
    [self updateSelectionToCurrentMatch];
}

// --- Trigger Search ---
- (void)searchAction:(id)sender
{
    var searchString = [sender stringValue];
    var isNameOnly = [_nameOnlyCheckbox state] === CPOnState;
    
    if (!searchString || [searchString length] === 0)
    {
        [treeController setSelectionIndexPaths:[]];
        _matchedIndexPaths = [];
        _currentMatchIndex = -1;
        [_searchStatusLabel setStringValue:@""];
        return;
    }
    CPLog("Suche läuft...");
    [_searchStatusLabel setStringValue:@"Searching..."];

    var urlString = "/DBB/hpo/search/" + encodeURIComponent(searchString) + "?nameOnly=" + (isNameOnly ? "1" : "0");
    var request = [CPURLRequest requestWithURL:urlString];

    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error) {
                                if (!error && data) {
                                    var json = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                    [self expandAndSelectPaths:json];
                                } else {
                                    CPLog("Fehler bei der Suche.");
                                    [_searchStatusLabel setStringValue:@"Error"];
                                }
                            }];
}

// --- Delegate Method: Triggers when the user selects a row ---
- (void)outlineViewSelectionDidChange:(CPNotification)notification
{
    var selectedRow = [outlineView selectedRow];

    if (selectedRow === -1) {
        // Clear all data if deselected
        _synonyms = [];
        _xrefs = [];
        _downstreamTerms = [];
        [definitionTextView setString:@""]; // Clear definition text
        
        [synonymsTableView reloadData];
        [xrefsTableView reloadData];
        [downstreamTableView reloadData];
        return;
    }
    
    var item = [outlineView itemAtRow:selectedRow];
    var node = [item representedObject];
    
    [definitionTextView setString:[node definition] || @"No definition available."];
    
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
                           completionHandler:function(response, data, error) {
        if (!error && data) {
            _downstreamTerms = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil] ||[];
        }
        else {
            _downstreamTerms = [];
        }
        [downstreamTableView reloadData];
    }];
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
    if (!treeNode) return;
    
    var mutableChildNodes = [treeNode mutableChildNodes];
    
    // Safety check: ensure we are operating on the CPTreeNode proxy using proper Obj-J methods
    if ([mutableChildNodes count] > 0)
    {
        var firstChildObj = [[mutableChildNodes objectAtIndex:0] representedObject];
        if ([firstChildObj name] !== @"Loading...") {
            return; // Already synced
        }
    } else if ([mutableChildNodes count] === 0 && [newChildren count] === 0) {
        return; // Empty node
    }

    // Clear the dummy proxy
    [mutableChildNodes removeAllObjects];
    
    for (var i = 0; i < [newChildren count]; i++) {
        var childModel = newChildren[i];
        var childTreeNode = [[CPTreeNode alloc] initWithRepresentedObject:childModel];
        
        // If the model is not a leaf, recreate its dummy proxy so the UI draws a disclosure triangle
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

    // 1. CACHED DATA: Sync the tree node synchronously.
    // The outline view will immediately animate the expansion of the REAL children.
    if ([node hasLoadedChildren]) {
        [self syncTreeNode:anItem withModelChildren:[node children]];
        return YES;
    }

    // 2. ASYNC FETCH: We let the method return YES immediately so the Outline View 
    // begins sliding down the "Loading..." dummy row.
    // We record the time so we don't interrupt the animation prematurely.
    var expandStartTime = [CPDate timeIntervalSinceReferenceDate];

    [node fetchChildrenWithCompletion:function(newChildren) {
        
        var elapsed = [CPDate timeIntervalSinceReferenceDate] - expandStartTime;
        var animationDuration = 0.25; // CPOutlineView default animation duration
        
        // If the fetch was faster than the animation, calculate the remaining time
        // Add a tiny 50ms buffer to guarantee the animation has completely cleared.
        var delay = MAX(0, animationDuration - elapsed + 0.05);
        
        setTimeout(function() {
            // Replace the "Loading..." proxy with the real ones
            [self syncTreeNode:anItem withModelChildren:newChildren];
            
            // Refresh the outline view to snap the new rows in
            [anOutlineView reloadItem:anItem reloadChildren:YES];
            
        }, delay * 1000); // setTimeout uses milliseconds
    }];
    
    return YES;
}

// --- 3. Fixed resolvePath: ensuring background searches build the proxy tree ---
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
            
            // CRITICAL FIX: Ensure the CPTreeNode proxy exists for the deep path so updateSelectionToCurrentMatch can find it later
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
    if (!_matchedIndexPaths || [_matchedIndexPaths count] === 0) {
        [_searchStatusLabel setStringValue:@"0 of 0"];
        return;
    }
    
    var path = _matchedIndexPaths[_currentMatchIndex];
    
    // Iteratively expand parents
    var partialPath = [CPIndexPath indexPathWithIndex:[path indexAtPosition:0]];
    for (var level = 1; level < [path length]; level++) {
        var treeNode = [[treeController arrangedObjects] descendantNodeAtIndexPath:partialPath];
        if (treeNode) {
            [outlineView expandItem:treeNode];
        }
        partialPath = [partialPath indexPathByAddingIndex:[path indexAtPosition:level]];
    }
    
    // Select the target item
    [treeController setSelectionIndexPath:path];
    [_searchStatusLabel setStringValue:(_currentMatchIndex + 1) + @" of " + [_matchedIndexPaths count]];
    
    // Give the view layout engine time to create the visual rows before attempting to scroll to them
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
        [_searchStatusLabel setStringValue:@"0 hits"];
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

            if (finalIndexPath) {
                [targetIndexPaths addObject:finalIndexPath];
            }

            pendingPaths--;
            
            if (pendingPaths === 0)
            {
                _matchedIndexPaths = targetIndexPaths;
                _currentMatchIndex = 0;
                
                // crucial: Give CPTreeController's KVO time to process all the loaded children 
                // BEFORE attempting to traverse descendantNodeAtIndexPath in the update method.
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
        definition = dict.definition || @""; // Automatically parsed from JSON data if available
        
        // is_leaf is 0 for nodes with children, 1 for actual leaves
        isLeaf = (dict.is_leaf == 1); 
        
        if (!isLeaf)
        {
            // Inject a placeholder so CPTreeController sees count > 0 
            // and shows the disclosure triangle.
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

// Helper init for our placeholder node
- (id)initAsDummy
{
    self = [super init];

    if (self)
    {
        name = @"Loading...";
        definition = @"";
        isLeaf = YES;
        children = [];
        hasLoadedChildren = YES; // Prevent the app from trying to fetch children for the dummy node
    }
    return self;
}

// Explicit KVO-compliant accessors for children array
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
    // 1. If already loaded, return immediately
    if (hasLoadedChildren) {
        if (completion) completion(children);
        return;
    }

    // 2. Queue the callback
    if (!_fetchCallbacks)
    {
        _fetchCallbacks = [];
    }
    if (completion) {
        [_fetchCallbacks addObject:completion];
    }

    // 3. If already fetching, just wait for it to finish
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
            
            // Execute all queued callbacks
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
                callbacksToRun[i]([]); // Return empty on error to prevent hanging
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
