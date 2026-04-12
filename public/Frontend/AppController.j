@import <AppKit/AppKit.j>
@import <Foundation/CPObject.j>
@import <Renaissance/Renaissance.j>

@implementation AppController : CPObject
{
    CPTreeController treeController;
    CPOutlineView    outlineView;
    
    // UI Elements (Now all are Table Views)
    CPTableView      synonymsTableView;
    CPTableView      xrefsTableView;
    CPTableView      downstreamTableView;
    
    // Data stores
    CPArray          _allRoots;
    CPArray          _synonyms;
    CPArray          _xrefs;
    CPArray          _downstreamTerms;
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

    // 2. Setup the Search Field (Top)
    var searchField = [[CPSearchField alloc] initWithFrame:CGRectMake(20, 10, CGRectGetWidth(bounds) - 40, 30)];
    [searchField setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [searchField setPlaceholderString:@"Filter Roots..."];
    [searchField setTarget:self];
    [searchField setAction:@selector(searchAction:)];
    [contentView addSubview:searchField];

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

    // SECTION 3.1: Xrefs TableView (Modified from TokenField)
    var xrefScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight * 0.20)];
    [xrefScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [xrefScroll setAutohidesScrollers:YES];
    
    xrefsTableView = [[CPTableView alloc] initWithFrame:[xrefScroll bounds]];
    var xrefCol = [[CPTableColumn alloc] initWithIdentifier:@"xref"];
    [[xrefCol headerView] setStringValue:@"Cross References"];
    [xrefCol setWidth:rightWidth - 5];
    [xrefsTableView addTableColumn:xrefCol];
    [xrefsTableView setDataSource:self];
    [xrefScroll setDocumentView:xrefsTableView];
    
    // Create a generic wrapper to hold title + ScrollView
    var xrefBox = [[CPBox alloc] initWithFrame:CGRectMake(0,0, rightWidth, splitHeight * 0.20)];
    [xrefBox setTitle:@"Cross References (Xrefs)"];
    [xrefBox setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [[xrefBox contentView] addSubview:xrefScroll];
    
    [rightSplitView addSubview:xrefBox];

    // SECTION 3.2: Synonyms TableView
    var synScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight * 0.40)];
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

    // SECTION 3.3: Downstream Codes TableView (Modified from TextView)
    var downScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight * 0.40)];
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
    
    // Add wrapper box for the Text View
    var textBox = [[CPBox alloc] initWithFrame:CGRectMake(0,0, rightWidth, splitHeight * 0.40)];
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


// --- TableView Data Source (Synonyms, Xrefs, Downstream) ---

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
    var request =[CPURLRequest requestWithURL:"/DBB/hpo/roots"];
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

- (void)searchAction:(id)sender
{
    var searchString = [sender stringValue];
    
    if (!searchString || [searchString length] === 0)
    {
        // Wenn das Suchfeld leer ist, leeren wir die Selektion
        [treeController setSelectionIndexPaths:[]];
        return;
    }
    CPLog("Suche läuft...");

    var urlString = "/DBB/hpo/search/" + encodeURIComponent(searchString);
    var request = [CPURLRequest requestWithURL:urlString];

    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error) {
                                if (!error && data) {
                                    var json =[CPJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                    [self expandAndSelectPaths:json];
                                } else {
                                    CPLog("Fehler bei der Suche.");
                                }
                            }];
}

- (void)expandAndSelectPaths:(CPArray)searchResults
{
    // Sicherstellen, dass searchResults nicht null oder undefiniert ist
    if (!searchResults || searchResults.length === 0)
    {
        CPLog("Keine Treffer gefunden oder ungültige Server-Antwort.");
        [treeController setSelectionIndexPaths:[]];
        return;
    }
    CPLog(searchResults.length + " Treffer gefunden. Lade Baumstruktur...");

    var targetIndexPaths = [CPMutableArray array];
    var pendingPaths = searchResults.length;

    // Wir gehen jeden gefundenen Pfad einzeln durch
    for (var i = 0; i < searchResults.length; i++)
    {
        var nodeIds = searchResults[i].path; // z.B. [RootID, ChildID, MatchID]

        [self resolvePath:nodeIds
             currentIndex:0
            currentModels:_allRoots
            baseIndexPath:nil
               completion:function(finalIndexPath) {

                        if (finalIndexPath) {
                            [targetIndexPaths addObject:finalIndexPath];
                        }

            pendingPaths--;
            
            // Wenn alle Pfade fertig aufgelöst wurden, markieren wir sie im TreeController
            if (pendingPaths === 0)
            {
                // 1. Selektion im Model setzen
                [treeController setSelectionIndexPaths:targetIndexPaths];

                // 2. Visuelles Aufklappen im CPOutlineView erzwingen
                for (var idx = 0; idx < targetIndexPaths.length; idx++) {
                    var currentPath = targetIndexPaths[idx];
                    
                    // Wir starten bei der Wurzel (Ebene 0)
                    var partialPath = [CPIndexPath indexPathWithIndex:[currentPath indexAtPosition:0]];

                    // Wir gehen den Pfad hinab und klappen jeden Knoten auf
                    // (außer den letzten Knoten selbst, der ist ja der Treffer)
                    for (var level = 1; level < [currentPath length]; level++)
                    {
                        var treeNode = [[treeController arrangedObjects] descendantNodeAtIndexPath:partialPath];
                        if (treeNode)
                        {
                            [outlineView expandItem:treeNode];
                        }
                        // Nächste Ebene anhängen
                        partialPath = [partialPath indexPathByAddingIndex:[currentPath indexAtPosition:level]];
                    }
                }
                
                // 3. Zum ersten Treffer scrollen, damit der Nutzer ihn sofort sieht!
                if (targetIndexPaths.length > 0) {
                    var firstMatchNode = [[treeController arrangedObjects] descendantNodeAtIndexPath:targetIndexPaths[0]];
                    var rowIndex = [outlineView rowForItem:firstMatchNode];
                    
                    if (rowIndex >= 0) {
                        [outlineView scrollRowToVisible:rowIndex];
                    }
                }

                CPLog("Alle Treffer markiert und aufgeklappt.");            
            }
        }];
    }
}

- (void)resolvePath:(CPArray)nodeIds currentIndex:(int)index currentModels:(CPArray)models baseIndexPath:(NSIndexPath)indexPath completion:(Function)callback
{
    if (index >= nodeIds.length)
    {
        callback(indexPath);
        return;
    }

    var targetId = parseInt(nodeIds[index], 10);
    var foundModelIndex = -1;
    var foundModel = nil;

    // Finde das Modell mit der aktuellen ID in der aktuellen Ebene
    for (var i = 0; i < models.length; i++)
    {
        if ([models[i] termId] === targetId)
        {
            foundModelIndex = i;
            foundModel = models[i];
            break;
        }
    }

    // Wenn der Knoten nicht gefunden wurde (Daten inkonsistent), brechen wir diesen Pfad ab
    if (!foundModel)
    {
        callback(nil);
        return;
    }

    // CPIndexPath erweitern
    var nextIndexPath = indexPath ? [indexPath indexPathByAddingIndex:foundModelIndex] : [CPIndexPath indexPathWithIndex:foundModelIndex];

    // Sind wir am Ende des Pfades angekommen? (Das ist unser Treffer)
    if (index === nodeIds.length - 1)
    {
        callback(nextIndexPath);
    } 
    else
    {
        // Wir müssen tiefer in den Baum. Sind die Kinder schon geladen?
        if ([foundModel hasLoadedChildren])
        {
            [self resolvePath:nodeIds currentIndex:(index + 1) currentModels:[foundModel children] baseIndexPath:nextIndexPath completion:callback];
        }
        else
        {
            // Kinder asynchron vom Server laden
            [foundModel fetchChildrenWithCompletion:function(newChildren) {
                            [self resolvePath:nodeIds currentIndex:(index + 1) currentModels:newChildren baseIndexPath:nextIndexPath completion:callback];
                      }];
        }
    }
}

// --- Delegate Method: Triggers when the user selects a row ---
- (void)outlineViewSelectionDidChange:(CPNotification)notification
{
    var selectedRow =[outlineView selectedRow];
    
    if (selectedRow === -1) {
        _synonyms = [];
        _xrefs = [];
        _downstreamTerms = [];
        [synonymsTableView reloadData];
        [xrefsTableView reloadData];
        [downstreamTableView reloadData];
        return;
    }
    
    var item =[outlineView itemAtRow:selectedRow];
    var node = [item representedObject];
    
    // Fetch all metadata in parallel
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
            _downstreamTerms = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil] || [];
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
            _synonyms = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil] || [];
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
        }
        [xrefsTableView reloadData];
    }];
}

- (BOOL)outlineView:(CPOutlineView)anOutlineView shouldExpandItem:(id)anItem
{
    var node = [anItem representedObject];
    
    if (node && ![node isLeaf] && ![node hasLoadedChildren])
    {
        [node fetchChildrenWithCompletion:function(newChildren) {
            var mutableChildNodes = [anItem mutableChildNodes];
            [mutableChildNodes removeAllObjects];
            
            for (var i = 0; i < newChildren.length; i++) {
                var childModel = newChildren[i];
                var childTreeNode = [[CPTreeNode alloc] initWithRepresentedObject:childModel];
                
                // If it's a branch, manually inject the dummy tree node
                if (![childModel isLeaf] && [[childModel children] count] > 0) {
                    var dummyModel = [childModel children][0];
                    var dummyTreeNode = [[CPTreeNode alloc] initWithRepresentedObject:dummyModel];
                    [[childTreeNode mutableChildNodes] addObject:dummyTreeNode];
                }
                [mutableChildNodes addObject:childTreeNode];
            }
            [anOutlineView reloadItem:anItem reloadChildren:YES];
        }];
    }
    return YES;
}
@end

// --- Custom Data Model representing a single HPO Node ---
@implementation HPONode : CPObject
{
    int      termId            @accessors(property=termId);
    CPString name              @accessors(property=name);
    BOOL     isLeaf            @accessors(property=isLeaf);
    CPArray  children;
    BOOL     hasLoadedChildren @accessors(property=hasLoadedChildren);
}

- (id)initWithDict:(JSObject)dict
{
    self = [super init];

    if (self)
    {
        termId = dict.id;
        name = dict.label;
        
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
        isLeaf = YES;
        children =[];
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
    if (hasLoadedChildren)
        return;

    hasLoadedChildren = YES; // Mark early to prevent duplicate fetching

    var urlString = "/DBB/hpo/children/" + termId;
    var request =[CPURLRequest requestWithURL:urlString];
    
    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error) {
        if (!error && data) {
            var json = [CPJSONSerialization JSONObjectWithData:data options:0 error:nil];
            var newChildren = [CPMutableArray array];
            
            for (var i = 0; i < json.length; i++) {
                var childNode = [[HPONode alloc] initWithDict:json[i]];
                [newChildren addObject:childNode];
            }
            
            // Update the model (fires KVO, but TreeController ignores it)
            [self setChildren:newChildren];
            
            // Ping the AppController that we are done
            if (completion) {
                completion(newChildren);
            }
        } else {
            hasLoadedChildren = NO; 
            CPLog("Failed to load children for term id %@: %@", termId, error);
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
