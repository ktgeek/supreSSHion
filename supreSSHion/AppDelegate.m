//
//  AppDelegate.m
//  supreSSHion
//
// MIT License
//
// Copyright (c) 2018 Keith Garner
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


#import "AppDelegate.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSMenu *statusMenu;
@end

@implementation AppDelegate

NSStatusBar *systemBar;
NSStatusItem *statusItem;

+ (void)initialize {
    systemBar = [NSStatusBar systemStatusBar];
    statusItem = [systemBar statusItemWithLength:(NSVariableStatusItemLength)];
}

- (IBAction)quitClicked:(NSMenuItem *)sender {
    [[NSApplication sharedApplication] terminate:(self)];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    //[statusItem setTitle:(@"suppreSSHion")];
    
    NSImage *icon = [NSImage imageNamed:(@"statusIcon")];
    [icon setTemplate:(true)];
    [statusItem setImage:(icon)];
    
    [statusItem setMenu:(_statusMenu)];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end
