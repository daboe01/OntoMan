@import <AppKit/AppKit.j>
@import <Foundation/CPObject.j>
@import <Renaissance/Renaissance.j>

@implementation AppController : CPObject
{
    CPTreeController treeController;
    CPOutlineView    outlineView;
    CPTextView       textView;
    
    CPArray          _allRoots; // Store roots locally so we can filter them
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    var theWindow = [[CPWindow alloc] initWithContentRect:CGRectMake(0, 0, 800, 600) styleMask:CPTitledWindowMask | CPResizableWindowMask];
    [theWindow setTitle:@"Human Phenotype Ontology"];
    [theWindow center];
    
    var contentView = [theWindow contentView];
    var bounds = [contentView bounds];

    // 1. Setup the Tree Controller
    treeController = [[CPTreeController alloc] init];
    [treeController setChildrenKeyPath:@"children"];
    [treeController setLeafKeyPath:@"isLeaf"];

    // 2. Setup the Search Field (Top)
    var searchField = [[CPSearchField alloc] initWithFrame:CGRectMake(20, 10, CGRectGetWidth(bounds) - 40, 30)];
    [searchField setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin]; // Pin to top
    [searchField setPlaceholderString:@"Filter Roots..."];
    [searchField setTarget:self];
    [searchField setAction:@selector(searchAction:)];
    [contentView addSubview:searchField];

    // 3. Setup Split View (Bottom)
    var splitView = [[CPSplitView alloc] initWithFrame:CGRectMake(20, 50, CGRectGetWidth(bounds) - 40, CGRectGetHeight(bounds) - 70)];
    [splitView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [splitView setVertical:YES]; // YES = Left/Right split panes

    // --- LEFT PANE: Outline View ---
    var leftScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, 400, CGRectGetHeight([splitView bounds]))];
    [leftScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [leftScroll setAutohidesScrollers:NO];

    outlineView = [[CPOutlineView alloc] initWithFrame:[leftScroll bounds]];
    var column = [[CPTableColumn alloc] initWithIdentifier:@"name"];
    [[column headerView] setStringValue:@"HPO Terms"];
    [column setWidth:380];

    [outlineView addTableColumn:column];
    [outlineView setOutlineTableColumn:column];
    [outlineView setAllowsMultipleSelection:NO];
    [outlineView setDelegate:self];

    [leftScroll setDocumentView:outlineView];
    [splitView addSubview:leftScroll];

    // --- RIGHT PANE: Text View ---
    var rightScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, 300, CGRectGetHeight([splitView bounds]))];
    [rightScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [rightScroll setAutohidesScrollers:YES];
    
    textView = [[CPTextView alloc] initWithFrame:[rightScroll bounds]];[textView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [textView setEditable:NO];
    [textView setFont:[CPFont fontWithName:@"Courier" size:12.0]];[textView setString:@"Select an HPO term to see downstream codes."];
    
    [rightScroll setDocumentView:textView];
    [splitView addSubview:rightScroll];

    [contentView addSubview:splitView];

    // 4. Establish Bindings
    [outlineView bind:@"content" toObject:treeController withKeyPath:@"arrangedObjects" options:nil];
    [outlineView bind:@"selectionIndexPaths" toObject:treeController withKeyPath:@"selectionIndexPaths" options:nil];

    [theWindow orderFront:self];

    // 5. Kick off loading the root nodes
    [self fetchRoots];
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

// --- NEU: Suche ans Backend senden ---
- (void)searchAction:(id)sender
{
    var searchString = [sender stringValue];
    
    if (!searchString || [searchString length] === 0)
    {
        // Wenn das Suchfeld leer ist, leeren wir die Selektion
        [treeController setSelectionIndexPaths:[]];
        return;
    }
    [textView setString:@"Suche läuft..."];

    var urlString = "/DBB/hpo/search/" + encodeURIComponent(searchString);
    var request = [CPURLRequest requestWithURL:urlString];

    [CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error) {
                                if (!error && data) {
                                    var json =[CPJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                    [self expandAndSelectPaths:json];
                                } else {
                                    [textView setString:@"Fehler bei der Suche."];
                                }
                            }];
}

- (void)expandAndSelectPaths:(CPArray)searchResults
{
    // Sicherstellen, dass searchResults nicht null oder undefiniert ist
    if (!searchResults || searchResults.length === 0)
    {
        [textView setString:@"Keine Treffer gefunden oder ungültige Server-Antwort."];
        [treeController setSelectionIndexPaths:[]];

        return;
    }
    if (searchResults.length === 0)
    {
        [textView setString:@"Keine Treffer gefunden."];
        [treeController setSelectionIndexPaths:[]];
        return;
    }
    [textView setString:searchResults.length + @" Treffer gefunden. Lade Baumstruktur..."];

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

                [textView setString:@"Alle Treffer markiert und aufgeklappt."];            }
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
    
    if (selectedRow === -1) {[textView setString:@"Select an HPO term to see downstream codes."];
        return;
    }
    
    var item =[outlineView itemAtRow:selectedRow];
    var node = [item representedObject];
    
    if (node && ![node hasLoadedChildren] && [node isLeaf])
    {
        [textView setString:"ID: " + node.termId + " | " + node.name];
    } else {
        [self fetchDownstreamForNode:node];
    }
}

// --- Call your backend '/DBB/children/idparent/:pk' endpoint ---
- (void)fetchDownstreamForNode:(HPONode)node
{
    [textView setString:@"Loading downstream codes..."];

    var urlString = "/DBB/children/idparent/" + [node termId];
    var request = [CPURLRequest requestWithURL:urlString];[CPURLConnection sendAsynchronousRequest:request
                                       queue:[CPOperationQueue mainQueue]
                           completionHandler:function(response, data, error) {
        if (!error && data) {
            var json =[CPJSONSerialization JSONObjectWithData:data options:0 error:nil];
            
            var text = "Downstream terms for " +[node name] + ":\n";
            text += "----------------------------------------\n";
            
            for (var i = 0; i < json.length; i++) {
                text += "ID: " + json[i].id + " | " + json[i].label + "\n";
            }
            
            if (json.length === 0) {
                text = "No downstream codes found.";
            }
            
            [textView setString:text];
        } else
        {
            [textView setString:@"Failed to fetch downstream codes."];
        }
    }];
}

// --- Expansion Fix (From previous correction) ---
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
                }[mutableChildNodes addObject:childTreeNode];
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

/*!
    Parses a JSON string and returns a JavaScript Object / CPArray / CPDictionary.
    In Cappuccino, `data` from CPURLConnection is typically a CPString.
*/
+ (id)JSONObjectWithData:(CPString)data options:(int)options error:(id)error
{
    if (!data || [data length] === 0) {
        return nil;
    }

    try {
        // Bridge directly to the native browser JSON parser
        return JSON.parse(data);
    } 
    catch (e) {
        // In a more robust implementation, you would populate the 'error' reference here.
        CPLog.error(@"CPJSONSerialization Error parsing JSON: " + e.message);
        return nil;
    }
}

/*!
    Converts a JavaScript Object, CPArray, or CPDictionary back into a JSON string.
*/
+ (CPString)dataWithJSONObject:(id)object options:(int)options error:(id)error
{
    if (!object) {
        return nil;
    }

    try {
        // Bridge directly to the native browser JSON stringifier
        return JSON.stringify(object);
    } 
    catch (e) {
        CPLog.error(@"CPJSONSerialization Error stringifying object: " + e.message);
        return nil;
    }
}

/*!
    Validates whether a given object can be safely converted to JSON.
*/
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
