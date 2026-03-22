/*
 * Cappuccino frontend for HPO
 *
 * Created by daboe01 on Mar, 2017 by DB.
 * Copyright 2017, All rights reserved.
 *
 *
 */

// fixme:
// come on, there has to be something...


/////////////////////////////////////////////////////////

HostURL=""
BaseURL=HostURL+"/";

/////////////////////////////////////////////////////////

@import <Foundation/CPObject.j>
@import <Renaissance/Renaissance.j>

@implementation AppController : CPObject
{   id  store @accessors;

    id  mainWindow;
    id  searchTerm @accessors;

    id  entitiesController;
    id  childrenController;
    id  xrefsController;

    id  thaiController;

    id valiController
    id cleanedHPOController;
    id fragmentsController;
    id valiTextView;
}

- (void) applicationDidFinishLaunching:(CPNotification)aNotification
{
    store=[[FSStore alloc] initWithBaseURL: HostURL+"/DBB"];

    [CPBundle loadRessourceNamed: "model.gsmarkup" owner:self];

    var mainFile="gui.gsmarkup";
    var re = new RegExp("t=([^&#]+)");
    var m = re.exec(document.location);

    if (m)
        mainFile=m[1];

    [CPBundle loadRessourceNamed:mainFile owner:self];

    [fragmentsController addObserver:self forKeyPath:"selection" options:nil context:nil];
}

-(void)markNOP:(id)sender
{
    [thaiController setValue:[[CPDate new] description] forKeyPath:"selection.resolved_date"];
    [thaiController setValue:'0' forKeyPath:"selection.corrected_hpo"];
}
-(void)markOOV:(id)sender
{
    [thaiController setValue:[[CPDate new] description] forKeyPath:"selection.resolved_date"];
    [thaiController setValue:'9999999' forKeyPath:"selection.corrected_hpo"];
}
-(void)markFinished:(id)sender
{
    [thaiController setValue:[[CPDate new] description] forKeyPath:"selection.resolved_date"];
}

- (void)setSearchTerm:(CPString)aTerm
{
    if(aTerm && aTerm.length)
    {
        setTimeout(function()
                   {
            [entitiesController setFilterPredicate:[CPPredicate predicateWithFormat:"label CONTAINS[cd] %@", aTerm.toLowerCase()]]
        }, 100);
    }
    else
        [entitiesController setFilterPredicate:nil];
}

// observed
- (void)observeValueForKeyPath:(CPString)keyPath ofObject:(id)object change:(id)change context:(id)context
{
    if (object == fragmentsController)
    {
        [valiTextView setSelectedRange:_MakeRangeFromAbs([fragmentsController valueForKeyPath:"selection.start_index"], [fragmentsController valueForKeyPath:"selection.end_index"])];
    }
}

- (CPString)_comboBox:(CPComboBox)aComboBox completedString:(CPString)uncompletedString force:(BOOL)forceFlag
{
    if(uncompletedString)
    {
        [cleanedHPOController setFilterPredicate:[CPPredicate predicateWithFormat:"label BEGINSWITH[cd] %@ and code_system = %@", uncompletedString, [valiController valueForKeyPath:"selection.source"]]];

        if (![[cleanedHPOController arrangedObjects] count])
            [cleanedHPOController setFilterPredicate:[CPPredicate predicateWithFormat:"label CONTAINS[cd] %@ and code_system = %@", uncompletedString, [valiController valueForKeyPath:"selection.source"]]];

    }
}
- (void)takeHPOCode:(id)sender
{

    var hpoCode = [sender stringValue];
    var selection = [valiTextView selectedRange];
    var text = [[[valiTextView textStorage] attributedSubstringFromRange:selection] string];

    if (hpoCode && text)
    {
        [fragmentsController addObject:@{"hpo_code": hpoCode, "content": text, "start_index": selection.location, "end_index": selection.location + selection.length}];
    }
    else {
        [[CPAlert alertWithError:"Please select some text and choose a HPO code."] runModal];
    }
}
@end

//
//
//

var CPComboBoxCompletionTestCI = function(object, index, context)
{
    return object.toString().toLowerCase().indexOf(context.toLowerCase()) === 0;
};


@class CPComboBox;
@implementation CIComboBox: CPComboBox

- (CPString)completedString:(CPString)substring
{
    if (_usesDataSource)
        return [self comboBoxCompletedString:substring];
    else
    {
        if (_target && [_target respondsToSelector:@selector(_comboBox:completedString:force:)]);
        [_target _comboBox:self completedString:substring force:NO];

        var index = [_items indexOfObjectPassingTest:CPComboBoxCompletionTestCI context:substring];

        if (index !== CPNotFound && ![self listIsVisible])
        {
            [self setNumberOfVisibleItems:10];
            [self popUpList];
        }

        return index !== CPNotFound ? _items[index] : nil;
    }
}
- (void)popUpList
{
    if(_target && [_target respondsToSelector:@selector(_comboBox:completedString:force:)]);
    {
        var selectedRange = [self selectedRange];
        var str = [self stringValue];

        if (selectedRange.length > 0 && selectedRange.location > 0)
            str = [str substringWithRange:CPMakeRange(0, selectedRange.location)];

        [_target _comboBox:self completedString:str force:YES];
    }

    [super popUpList]
}

@end

@class GSComboBoxTagValue;
@implementation CIComboBoxTagValue: GSComboBoxTagValue

- (CPString)completedString:(CPString)substring
{
    if (_usesDataSource)
        return [self comboBoxCompletedString:substring];
    else
    {
        if (_target && [_target respondsToSelector:@selector(_comboBox:completedString:force:)]);
        [_target _comboBox:self completedString:substring force:NO];

        var index = [_items indexOfObjectPassingTest:CPComboBoxCompletionTestCI context:substring];

        if (index !== CPNotFound && ![self listIsVisible])
        {
            [self setNumberOfVisibleItems:10];
            [self popUpList];
        }

        return index !== CPNotFound ? _items[index] : nil;
    }
}
- (void)popUpList
{
    if(_target && [_target respondsToSelector:@selector(_comboBox:completedString:force:)]);
    {
        var selectedRange = [self selectedRange];
        var str = [self stringValue];

        if (selectedRange.length > 0 && selectedRange.location > 0)
            str = [str substringWithRange:CPMakeRange(0, selectedRange.location)];

        [_target _comboBox:self completedString:str force:YES];
    }

    [super popUpList]
}
@end


@implementation GSMarkupTagComboBoxCI: GSMarkupTagComboBox

+ (Class) platformObjectClass
{
    return [CIComboBox class];
}
@end
