
@import <Foundation/CPObject.j>
@import <Foundation/CPAttributedString.j>

var  _regexColors;

@implementation ColorizingTextView : CPTextView
{
}

+ (void)initialize
{
        _regexColors = @{
                         '1s':  [ /<N.>(.+?)<.N.>/gi,              [CPColor colorWithHexString:"8DD3C7"] ],
                         '2s':  [ /<MED>(.+?)<.MED>/gi,            [CPColor colorWithHexString:"BEBADA"] ],
                         '7s':  [ /<ANATOM>(.+?)<.ANATOM>/gi,      [CPColor colorWithHexString:"FB8072"] ],
                         '4s':  [ /<LOC>(.+?)<.LOC+>/gi,           [CPColor colorWithHexString:"FB8072"] ],
                         '5s':  [ /<DIAG>(.+?)<.DIAG>/gi,          [CPColor colorWithHexString:"80B1D3"] ],
                         '6s':  [ /<AD.>(.+?)<.AD.>/gi,            [CPColor colorWithHexString:"FDB462"] ],
                         '7s':  [ /<befund>(.+?)<.befund>/gi,      [CPColor colorWithHexString:"B3DE69"] ]
                        };
}

- (CPAttributedString) colorizedStringForString:(CPString)str
{
    var keys = [[_regexColors allKeys] sortedArrayUsingSelector:@selector(compare:)],
        result = [[CPAttributedString alloc] initWithString:str];
    [keys enumerateObjectsUsingBlock:function(key, idx, stop)
    {
        var val = [_regexColors objectForKey:key],
            re  = val[0],
            col = val[1],
            match;

        while (( match = re.exec(str)) != null)
        {
            [result setAttributes:@{CPForegroundColorAttributeName:col} range:CPMakeRange(match.index, match[0].length)];
        }
    }];
    var match;
    if(_delegate && [_delegate respondsToSelector:@selector(shoudHideTags)] && [_delegate shoudHideTags])
        while (( match =  /(<[^>]+>)/gi.exec(result._string)) != null)
            [result replaceCharactersInRange:CPMakeRange(match.index, match[0].length) withString:''];

    
    return result;
}

- (void)setObjectValue:(CPString)aString
{
    [_textStorage beginEditing];
    [_textStorage replaceCharactersInRange:CPMakeRange(0, [_layoutManager numberOfCharacters]) withAttributedString:[self colorizedStringForString:aString]];
    [_textStorage endEditing];
    [self setSelectedRange:CPMakeRange(0,0)]
}

@end

@implementation GSMarkupTagColorizingTextView:GSMarkupTagTextView
+ (CPString) tagName
{	return @"colorizingTextView";
}

+ (Class) platformObjectClass
{	return [ColorizingTextView class];
}

@end
