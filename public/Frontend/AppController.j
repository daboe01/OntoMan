/*
 * Cappuccino frontend for NLP
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
@import "ColorizingTextView.j"

@implementation SessionStore : FSStore 

-(CPURLRequest) requestForAddressingObjectsWithKey: aKey equallingValue: (id) someval inEntity:(FSEntity) someEntity
{    var request = [CPURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+aKey+"/"+someval+"?session="+ window.G_SESSION];
    return request;
}
-(CPURLRequest) requestForFuzzilyAddressingObjectsWithKey: aKey equallingValue: (id) someval inEntity:(FSEntity) someEntity
{    var request = [CPURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+aKey+"/like/"+someval+"?session="+ window.G_SESSION];
    return request;
}
-(CPURLRequest) requestForAddressingAllObjectsInEntity:(FSEntity) someEntity
{    return [CPURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"?session="+ window.G_SESSION ];
}

@end


@implementation AppController : CPObject
{   id  store @accessors;

    id  mainWindow;
    id  textView;
    id  tagsSwitch;

    id  documentsController;
    id  diagnosesController;
}

- (void) applicationDidFinishLaunching:(CPNotification)aNotification
{    store=[[SessionStore alloc] initWithBaseURL: HostURL+"/DBB"];

    [CPBundle loadRessourceNamed: "model.gsmarkup" owner:self];

    var mainFile="gui.gsmarkup";
    var re = new RegExp("t=([^&#]+)");
    var m = re.exec(document.location);
    if(m) mainFile=m[1];
    [CPBundle loadRessourceNamed:mainFile owner:self ];

}
-(void)toggleTags:(id)sender
{
    [textView _reverseSetBinding];
}
    
-(BOOL)shoudHideTags
{
    return !![tagsSwitch state];
}

-(void) connection:(CPConnection)someConnection didReceiveData:(CPData)data
{

    /*
    if(someConnection == _addingConnection)
    {   _addingConnection = nil;
        [personsController reload];
        [personsEmailsController reload];
        [emailTagsController reload];
    }
    */
   // [progress stopAnimation: self];
}

@end
