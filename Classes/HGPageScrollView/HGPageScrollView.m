//
//  HGPageScrollView.m
//  HGPageDeckSample
//
//  Created by Rotem Rubnov on 25/10/2010.
//  Copyright (C) 2010 100 grams software. All rights reserved.
//
//	Permission is hereby granted, free of charge, to any person obtaining a copy
//	of this software and associated documentation files (the "Software"), to deal
//	in the Software without restriction, including without limitation the rights
//	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//	copies of the Software, and to permit persons to whom the Software is
//	furnished to do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in
//	all copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//	THE SOFTWARE.
//

#import "HGPageScrollView.h"
#import <QuartzCore/QuartzCore.h>
#import "ArticleView.h"
#import "TransparentToolbar.h"

// -----------------------------------------------------------------------------------------------------------------------------------
//Internal view class, used by to HGPageScrollView.

#define MAX_TABS    5
#pragma mark HGTouchView

@interface HGTouchView : UIView {
    NSTimer *_closeTimer;
}
@property (nonatomic, strong) UIView *receiver;
@property (nonatomic, strong) NSTimer *closeTimer;
@end



@implementation HGTouchView

@synthesize receiver;
@synthesize closeTimer = _closeTimer;

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if ([self pointInside:point withEvent:event]) {
		return self.receiver;
        NSLog(@"touched %@ receiver %@", self, [self receiver]);
	}
	return nil;
}

@end




// -----------------------------------------------------------------------------------------------------------------------------------
#pragma mark - HGPageScrollView private methods & properties

typedef enum{
    HGPageScrollViewUpdateMethodInsert, 
    HGPageScrollViewUpdateMethodDelete, 
    HGPageScrollViewUpdateMethodReload
}HGPageScrollViewUpdateMethod;


@interface HGPageScrollView()

// initializing/updating controls
- (void) initHeaderForPageAtIndex : (NSInteger) index;
- (void) initDeckTitlesForPageAtIndex : (NSInteger) index;

// insertion/deletion/update of pages
- (HGPageView*) loadPageAtIndex:(NSInteger)index insertIntoVisibleIndex:(NSInteger) visibleIndex;
- (void) addPageToScrollView : (HGPageView*) page atIndex : (NSInteger) index;
- (void) insertPageInScrollView:(HGPageView *)page atIndex:(NSInteger) index animated:(BOOL)animated;
- (void) removePagesFromScrollView:(NSArray*)pages animated:(BOOL)animated;
- (void) setFrameForPage:(UIView*)page atIndex:(NSInteger)index;
- (void) shiftPage : (UIView*) page withOffset : (CGFloat) offset;
- (void) setNumberOfPages : (NSInteger) number; 
- (void) updateScrolledPage : (HGPageView*) page index : (NSInteger) index;
- (void) prepareForDataUpdate : (HGPageScrollViewUpdateMethod) method withIndexSet : (NSIndexSet*) set;

// managing selection and scrolling
- (void) updateVisiblePages;
- (void) setAlphaForPage : (UIView*) page;
- (void) preparePage : (HGPageView *) page forMode : (HGPageScrollViewMode) mode; 
- (void) setViewMode:(HGPageScrollViewMode)mode animated:(BOOL)animated; //toggles selection/deselection

// responding to actions 
- (void) didChangePageValue : (id) sender;

@property (nonatomic, strong) NSIndexSet *indexesBeforeVisibleRange; 
@property (nonatomic, strong) NSIndexSet *indexesWithinVisibleRange; 
@property (nonatomic, strong) NSIndexSet *indexesAfterVisibleRange; 
@property (nonatomic, readwrite) HGPageScrollViewMode viewMode;
@end



// -----------------------------------------------------------------------------------------------------------------------------------
#pragma mark - HGPageScrollView exception constants

#define kExceptionNameInvalidOperation   @"HGPageScrollView Invalid Operation"
#define kExceptionReasonInvalidOperation @"Updating HGPageScrollView data is only allowed in DECK mode, i.e. when the page scroller is visible."

#define kExceptionNameInvalidUpdate   @"HGPageScrollView DeletePagesAtIndexes Invalid Update"
#define kExceptionReasonInvalidUpdate @"The number of pages contained HGPageScrollView after the update (%d) must be equal to the number of pages contained in it before the update (%d), plus or minus the number of pages added or removed from it (%d added, %d removed)."



// -----------------------------------------------------------------------------------------------------------------------------------
#pragma mark -
#pragma mark - HGPageScrollView implementation 

@implementation HGPageScrollView


@synthesize pageHeaderView			= _pageHeaderView; 
@synthesize pageDeckBackgroundView	= _pageDeckBackgroundView;
@synthesize dataSource				= _dataSource;
@synthesize delegate				= _delegate;

@synthesize indexesBeforeVisibleRange;
@synthesize indexesWithinVisibleRange;
@synthesize indexesAfterVisibleRange; 

@synthesize isRotating;

@synthesize addTabButton = _newTabButton;


- (void) didRotate:(NSNotification*)notification {
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    if (!UIInterfaceOrientationIsPortrait(orientation) && !UIInterfaceOrientationIsLandscape(orientation)) {
        
        return;
    }
    if (![self.delegate shouldAutorotateToInterfaceOrientation:orientation]) {
        // auto rotate is off
        return;
    }
    _lastOrientation = orientation;
    BOOL value;
	id key = DefaultsGet(@"rotationLock");
	if (!key)
		value = NO;
	else {
		value = [key boolValue];
	}
	if (value) return;
    if (!_selectedPage) return;
    if (self.viewMode == HGPageScrollViewModePage) {
        if (!_selectedPage.superview) {
            [_visiblePages addObject:_selectedPage];
            [self addSubview:_selectedPage];
        }
        [(ArticleView*)_selectedPage didRotate:nil];
    }

    NSInteger index = [self indexForSelectedPage];
    if (index != NSNotFound) {
        [self layoutDeck];
        _selectedPage = [self pageAtIndex:index];
        [self scrollToPageAtIndex:index animated:NO];
        [self setAlphaForPage:_selectedPage];
        
    }
}

- (void) layoutDeck {
    CGRect selfFrm = self.frame;
    CGFloat width = 0.0f;
    CGFloat height = 0.0f;
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    
    if (![self.delegate shouldAutorotateToInterfaceOrientation:orientation]) {
        // auto rotate is off
        orientation = _lastOrientation;
    }
    if (!UIInterfaceOrientationIsPortrait(orientation) && !UIInterfaceOrientationIsLandscape(orientation)) {
        orientation = _lastOrientation;
    }
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    {
		NSUInteger statusBar = HAS_IOS_7 ? 0 : 20;
		
        if (UIInterfaceOrientationIsLandscape(orientation)) {
            width = _miniScaleFactor * SCREEN_HEIGHT;
            height = _miniScaleFactor * (320 - 30 - statusBar);
            selfFrm.size.height = (320 - 30 - statusBar);
        }
        else {
			
            width = _miniScaleFactor * 320;
            height = _miniScaleFactor * (SCREEN_HEIGHT - statusBar - 44);
#if WIKI || WIKITRAVEL
            selfFrm.size.height = SCREEN_HEIGHT - statusBar - 44;
#else
            selfFrm.size.height = SCREEN_HEIGHT - statusBar - 88;
#endif
        }
    } else {
        if (UIInterfaceOrientationIsLandscape(orientation)) {
            width = _miniScaleFactor * SCREEN_HEIGHT;
            height = _miniScaleFactor * 768-44;
            selfFrm.size.height = 748-44;
        }
        else {
			NSUInteger statusBar = HAS_IOS_7 ? 0 : 20;
            width = _miniScaleFactor * 768;
            height = _miniScaleFactor * (SCREEN_HEIGHT - 44);
            selfFrm.size.height = (SCREEN_HEIGHT - statusBar - 44);
        }
    }
          
    self.frame = selfFrm;
    CGRect frm = _scrollView.frame;
    frm.size.width = width+2*_pageMargin;
    frm.size.height = height;
    
    frm.origin.x = (self.frame.size.width - frm.size.width) * 0.5;
    frm.origin.y = (self.frame.size.height - frm.size.height) * 0.5;
    _scrollView.frame = frm;
    
    _scrollView.contentSize = CGSizeMake(_numberOfPages * _scrollView.bounds.size.width, 50);
    for (int i = 0; i < [self numberOfPages]; i++) {
        //if (i != [self indexForSelectedPage]) {
            HGPageView *page = [self pageAtIndex:i];
            [self setFrameForPage:page atIndex:i];

        //}
    }
    
    frm = _pageSelector.frame;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        if (UIInterfaceOrientationIsLandscape(orientation)) {
            frm.origin.y = 220;
        } else {
            frm.origin.y = SCREEN_HEIGHT - 120;
        }
    } else {
        if (UIInterfaceOrientationIsPortrait(orientation)) {
            frm.origin.y = SCREEN_HEIGHT - 150;
        } else {
            frm.origin.y = 768 - 150;
        }
    }
    
    _pageSelector.frame = frm;
}

- (void) awakeFromNib{ 

	[super awakeFromNib];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didRotate:)name:UIDeviceOrientationDidChangeNotification object:nil];
    // release IB reference (we do not want to keep a circular reference to our delegate & dataSource, or it will prevent them from properly deallocating). 
	
	// init internal data structures
	_visiblePages = [[NSMutableArray alloc] initWithCapacity:3];
	_reusablePages = [[NSMutableDictionary alloc] initWithCapacity:3]; 
	_deletedPages = [[NSMutableArray alloc] initWithCapacity:0];
    
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        _miniScaleFactor = 0.7f;
        _pageMargin = 40.0f;
    } else {
        _miniScaleFactor = 0.6f;
        _pageMargin = 20.0f;
    }
    
    _scrollView.backgroundColor = [UIColor clearColor];
    _scrollView.scrollsToTop = NO;
    
	_pageDeckBackgroundView.backgroundColor = !HAS_IOS_7 ? [UIColor colorWithPatternImage:[UIImage imageNamed:@"tile_bg"]] : [UIColor colorWithWhite:0.25 alpha:0.7];
    _pageDeckBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    
    
    _pageDeckTitleLabel.shadowOffset = CGSizeMake(0, 1);
    _pageDeckTitleLabel.textColor = UIColorFromRGB(0xdfe1e5);
    _pageDeckTitleLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
    
	// set tap gesture recognizer for page selection
	UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGestureFrom:)];
	[_scrollView addGestureRecognizer:recognizer];
	recognizer.delegate = self;
	
	UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
	[_scrollView addGestureRecognizer:swipeUp];
	[swipeUp setDirection:UISwipeGestureRecognizerDirectionUp];
	swipeUp.delegate = self;
	
	// setup scrollView
	_scrollView.decelerationRate = 1.0;//UIScrollViewDecelerationRateNormal;
    _scrollView.delaysContentTouches = NO;
    _scrollView.clipsToBounds = NO;	
    _scrollView.maximumZoomScale = 2.0f;
	_scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; 
	_pageSelectorTouch.receiver = _pageSelector;
	_scrollViewTouch.receiver = _scrollView;
	
	// setup pageSelector
	[_pageSelector addTarget:self action:@selector(didChangePageValue:) forControlEvents:UIControlEventValueChanged];
	_pageSelector.hidden = YES;
	// default number of pages 
	_numberOfPages = 1;
	
	// set initial visible indexes (page 0)
	_visibleIndexes.location = 0;
	_visibleIndexes.length = 1;
	
    // set initial view mode
    self.viewMode = HGPageScrollViewModeDeck;
    
	// load the data 
	[self reloadData];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        _toolbar = [[TransparentToolbar alloc] initWithFrame:CGRectMake(0, self.frame.size.height-44, self.frame.size.width, 44)];
        _toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
        _toolbar.translucent = YES;
        _toolbar.opaque = NO;
        _toolbar.backgroundColor = [UIColor clearColor];
        
        
        [self addSubview:_toolbar];
        
    }


}

- (void) setAddTabButton:(UIBarButtonItem *)newTabButton {
    if (_newTabButton) {
         _newTabButton = nil;
    }
    _newTabButton = newTabButton;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        
        UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self.delegate action:@selector(doneButton:)];
        
        UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        UIBarButtonItem *fixedSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        fixedSpace.width = 5.0f;
        [_toolbar setItems:@[fixedSpace,_newTabButton,flexSpace,done,fixedSpace]];
    }
}


- (void)dealloc 
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
	_visiblePages = nil;
    _deletedPages = nil;
	_reusablePages = nil;
}


#pragma mark -
#pragma mark Info


- (NSInteger) numberOfPages; 
{
	return _numberOfPages;
}


- (HGPageView *)pageAtIndex:(NSInteger)index;
// returns nil if page is not visible or the index is out of range
{
	if (index == NSNotFound || index < _visibleIndexes.location || index > _visibleIndexes.location + _visibleIndexes.length-1) {
		return nil;
	}
	return _visiblePages[index-_visibleIndexes.location];
}



#pragma mark -
#pragma mark Page Selection


- (NSInteger)indexForSelectedPage;   
{
    return [self indexForVisiblePage : _selectedPage];
}

- (NSInteger)indexForVisiblePage : (HGPageView*) page;   
{
	NSInteger index = [_visiblePages indexOfObject:page];
	if (index != NSNotFound) {
        return _visibleIndexes.location + index;
    }
    return NSNotFound;
}



- (void) scrollToPageAtIndex : (NSInteger) index animated : (BOOL) animated; 
{
	CGPoint offset = CGPointMake(index * _scrollView.frame.size.width, 0);
	[_scrollView setContentOffset:offset animated:animated];
}


- (void) selectPageAtIndex : (NSInteger) index animated : (BOOL) animated;
{
    // ignore if there are no pages or index is invalid
    if (index == NSNotFound || _numberOfPages == 0) {
        return;
    }
    
	if (index != [self indexForSelectedPage]) {
        
        // rebuild _visibleIndexes
        BOOL isLastPage = (index == _numberOfPages-1);
        BOOL isFirstPage = (index == 0); 
        NSInteger selectedVisibleIndex; 
        if (_numberOfPages == 1) {
            _visibleIndexes.location = index;
            _visibleIndexes.length = 1;
            selectedVisibleIndex = 0;
        }
        else if (isLastPage) {
            _visibleIndexes.location = index-1;
            _visibleIndexes.length = 2;
            selectedVisibleIndex = 1;
        }
        else if(isFirstPage){
            _visibleIndexes.location = index;
            _visibleIndexes.length = 2;                
            selectedVisibleIndex = 0;
        }
        else{
            _visibleIndexes.location = index-1;
            _visibleIndexes.length = 3;           
            selectedVisibleIndex = 1;
        }
 
        // update the scrollView content offset
        _scrollView.contentOffset = CGPointMake(index * _scrollView.frame.size.width, 0);

        // reload the data for the new indexes
        [self reloadData];
        
        // update _selectedPage
        _selectedPage = _visiblePages[selectedVisibleIndex];
        
        // update the page selector (pageControl)
        [_pageSelector setCurrentPage:index];

	}
    
    [(ArticleView*)_selectedPage willSelectPage];
    
    [_toolbar setHidden:YES];
	[self setViewMode:HGPageScrollViewModePage animated:animated];
}


- (void) deselectPageAnimated : (BOOL) animated;
{
    // ignore if there are no pages or no _selectedPage
    if (!_selectedPage || _numberOfPages == 0) {
        return;
    }
    [_toolbar setHidden:NO];
    // Before moving back to DECK mode, refresh the selected page
    NSInteger visibleIndex = [_visiblePages indexOfObject:_selectedPage];
    NSInteger selectedPageScrollIndex = [self indexForSelectedPage];
    CGRect identityFrame = _selectedPage.identityFrame;
    
    [_selectedPage removeFromSuperview];
    [_visiblePages removeObject:_selectedPage];
    _selectedPage = [self loadPageAtIndex:selectedPageScrollIndex insertIntoVisibleIndex:visibleIndex];
    _selectedPage.identityFrame = identityFrame;
    //_selectedPage.frame = pageFrame;
    _selectedPage.frame = identityFrame;
    _selectedPage.alpha = 1.0;
    [self addSubview:_selectedPage];

	[self setViewMode:HGPageScrollViewModeDeck animated:animated];
}

- (void) deleteButtonPressed:(id)sender {
    DebugLog(@"fired %@ ", sender);
    [self.delegate removePageAtIndex:[self indexForSelectedPage]];
    [self deletePagesAtIndexes:[NSIndexSet indexSetWithIndex:[self indexForSelectedPage]] animated:YES];
    if ([self numberOfPages] == 0) {
        [self.delegate addNewTab:self];
    }
    if ([self numberOfPages] == 1) {
        [self selectPageAfterDelay:0.3];
    }
}

- (void) selectPageAfterDelay:(NSTimeInterval)delay {
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(setViewMode:animated:)]];
    [inv setTarget:self];
    [inv setSelector:@selector(setViewMode:animated:)];
    int mode = HGPageScrollViewModePage;
    [inv setArgument:&mode atIndex:2];
    BOOL animated = YES;
    [inv setArgument:&animated atIndex:3];
    [inv performSelector:@selector(invoke) withObject:nil afterDelay:delay];
}

- (void) preparePage : (HGPageView *) page forMode : (HGPageScrollViewMode) mode 
{
    // When a page is presented in HGPageScrollViewModePage mode, it is scaled up and is moved to a different superview. 
    // As it captures the full screen, it may be cropped to fit inside its new superview's frame. 
    // So when moving it back to HGPageScrollViewModeDeck, we restore the page's proportions to prepare it to Deck mode.  
	if (mode == HGPageScrollViewModeDeck /*&& 
        CGAffineTransformEqualToTransform(page.transform, CGAffineTransformIdentity)*/) {
        page.transform = CGAffineTransformIdentity;
        CGRect frm = page.identityFrame;
        UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
        if (![self.delegate shouldAutorotateToInterfaceOrientation:orientation]) {
            // auto rotate is off
            orientation = _lastOrientation;
        }
        if (!UIInterfaceOrientationIsPortrait(orientation) && !UIInterfaceOrientationIsLandscape(orientation)) {
            orientation = _lastOrientation;
        }
		NSUInteger statusBar = HAS_IOS_7 ? 0 : 20;
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
        {
            if (UIInterfaceOrientationIsLandscape(orientation)) {
                frm.size.width = SCREEN_HEIGHT;
                frm.size.height = 320 - 30 - statusBar;
            }
            else {
                frm.size.width = 320;
                frm.size.height = SCREEN_HEIGHT- statusBar - 44;
            }
        } else {
            if (UIInterfaceOrientationIsLandscape(orientation)) {
                frm.size.width = SCREEN_HEIGHT;
                frm.size.height = 748-44;
            }
            else {
                frm.size.width = 768;
                frm.size.height = SCREEN_HEIGHT - statusBar - 44;
            }
        }
            
        page.identityFrame = frm;
        
        page.frame = page.identityFrame;
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:page.bounds];
        page.layer.shadowPath = path.CGPath;
	}
    
}


- (void) setViewMode:(HGPageScrollViewMode)mode animated:(BOOL)animated;
{
	if (self.viewMode == mode) {
		return;
	}
	
	self.viewMode = mode;
    
	NSInteger selectedIndex = [self indexForSelectedPage];
    
    if (mode == HGPageScrollViewModeDeck) {
        [self layoutDeck];
        
    }
    
	if (_selectedPage) {
        [self preparePage:_selectedPage forMode:mode];
    }
    


	void (^SelectBlock)(void) = nil;
    
    if (mode==HGPageScrollViewModePage)
        SelectBlock = ^{
			[UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleDefault;
            
            [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

            UIView *headerView = _pageHeaderView;
            
            // move to HGPageScrollViewModePage
            if([self.delegate respondsToSelector:@selector(pageScrollView:willSelectPageAtIndex:)]) {
                [self.delegate pageScrollView:self willSelectPageAtIndex:selectedIndex];
            }				
            [_scrollView bringSubviewToFront:_selectedPage];
            if ([self.dataSource respondsToSelector:@selector(pageScrollView:headerViewForPageAtIndex:)]) {
                UIView *altHeaderView = [self.dataSource pageScrollView:self headerViewForPageAtIndex:selectedIndex];
                [_userHeaderView removeFromSuperview];
                _userHeaderView = nil;
               if (altHeaderView) {
                   //use the header view initialized by the dataSource 
                   _pageHeaderView.hidden = YES; 
                   _userHeaderView = altHeaderView;
                   CGRect frame = _userHeaderView.frame;
                   frame.origin.y = 0;
                   _userHeaderView.frame = frame; 
                   headerView = _userHeaderView;
                   [self addSubview : _userHeaderView];
                }
                else{
                    _pageHeaderView.hidden = NO; 
                    [self initHeaderForPageAtIndex:selectedIndex];
                }
            }
            else { //use the default header view
                _pageHeaderView.hidden = NO; 
                [self initHeaderForPageAtIndex:selectedIndex]; 
            }

            // scale the page up to it 1:1 (identity) scale
            _selectedPage.transform = CGAffineTransformIdentity; 
                    
            // adjust the frame
            CGRect frame = _selectedPage.frame;
            if (!CGRectEqualToRect(CGRectZero, frame)) {
            frame.origin.y = headerView.frame.size.height - _scrollView.frame.origin.y;
            frame.origin.x = -_scrollView.frame.origin.x + 
                [self indexForSelectedPage] * _scrollView.bounds.size.width;
            // store this frame for the backward animation
            _selectedPage.identityFrame = frame; 

            // finally crop frame to fit inside new superview (see CompletionBlock) 
            frame.size.height = self.frame.size.height - headerView.frame.size.height;
            
            _selectedPage.frame = frame;
            }

            
            // reveal the page header view
            headerView.alpha = 1.0;
            
            //remove unnecessary views
            [_scrollViewTouch removeFromSuperview];
            [_pageSelectorTouch removeFromSuperview];

        };
    else
        SelectBlock = ^{
#if defined(__IPHONE_7_0)
			[UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleLightContent;
#endif
            
            [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

            UIView *headerView = _userHeaderView?_userHeaderView:_pageHeaderView;
            
            // move to HGPageScrollViewModeDeck
            //_pageSelector.hidden = NO;
            _pageDeckTitleLabel.hidden = NO;
            _pageDeckSubtitleLabel.hidden = NO;
            [self initDeckTitlesForPageAtIndex:selectedIndex];
            
            // add the page back to the scrollView and transform it
            [_scrollView addSubview:_selectedPage];
            CGRect frame = _selectedPage.frame;
			NSUInteger statusBar = HAS_IOS_7 ? 0 : 20;
            if (frame.size.width == SCREEN_HEIGHT && UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
                frame.size.height = 320 - 30 - statusBar;
            _selectedPage.frame = frame;
            _selectedPage.transform = CGAffineTransformMakeScale(_miniScaleFactor-0.1f, _miniScaleFactor-0.1f);	
            frame = _selectedPage.frame;
            //frame.origin.y = 0;
            frame.origin.y = (self.frame.size.height - frame.size.height) * 0.5 - _scrollView.frame.origin.y;
            frame.origin.x = (self.frame.size.width - frame.size.width) * 0.5 - _scrollView.frame.origin.x 
            + [self indexForSelectedPage] * _scrollView.bounds.size.width;
            _selectedPage.frame = frame;
            
            // hide the page header view
            headerView.alpha = 0.0;	
            
            
            // notify the delegate
            if ([self.delegate respondsToSelector:@selector(pageScrollView:willDeselectPageAtIndex:)]) {
                [self.delegate pageScrollView:self willDeselectPageAtIndex:selectedIndex];
            }		
        };
	
	void (^CompletionBlock)(BOOL) = nil;
    if (mode==HGPageScrollViewModePage)
        CompletionBlock = ^(BOOL finished){
			[[UIApplication sharedApplication] endIgnoringInteractionEvents];

            UIView *headerView = _userHeaderView?_userHeaderView:_pageHeaderView;

            // set flags
            _pageDeckTitleLabel.hidden = YES;
            _pageDeckSubtitleLabel.hidden = YES;
            //_pageSelector.hidden = YES;
            _scrollView.scrollEnabled = NO;
            _selectedPage.alpha = 1.0;
            // copy _selectedPage up in the view hierarchy, to allow touch events on its entire frame 
            _selectedPage.frame = CGRectMake(0, headerView.frame.size.height, self.frame.size.width, self.frame.size.height);
            [self addSubview:_selectedPage];
            UIWebView *webView = [(ArticleView*)_selectedPage webView];
            webView.scrollView.scrollsToTop = YES;
            
            // notify delegate
            if ([self.delegate respondsToSelector:@selector(pageScrollView:didSelectPageAtIndex:)]) {
                [self.delegate pageScrollView:self didSelectPageAtIndex:selectedIndex];
            }		
        };
    else 
        CompletionBlock = ^(BOOL finished){
			[UIView animateWithDuration:0.1 animations:^(void) {
                _selectedPage.transform = CGAffineTransformMakeScale(_miniScaleFactor, _miniScaleFactor);	
                CGRect frame = _selectedPage.frame;
                frame.origin.y = (self.frame.size.height - frame.size.height) * 0.5 - _scrollView.frame.origin.y;
                frame.origin.x = (self.frame.size.width - frame.size.width) * 0.5 - _scrollView.frame.origin.x 
                    + [self indexForSelectedPage] * _scrollView.bounds.size.width;
                //frame.origin.x = (oldFrame.size.width - frame.size.width) * 0.5;
                _selectedPage.frame = frame;
            } completion:^(BOOL finished) {
                [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                _scrollView.scrollEnabled = YES;
                [self addSubview:_scrollViewTouch];
                [self addSubview: _pageSelectorTouch];
                if ([self.delegate respondsToSelector:@selector(pageScrollView:didDeselectPageAtIndex:)]) {
                    [self.delegate pageScrollView:self didDeselectPageAtIndex:selectedIndex];
                }
                
                UIWebView *webView = [(ArticleView*)_selectedPage webView];
                webView.scrollView.scrollsToTop = NO;
                
                [self bringSubviewToFront:_toolbar];
            }];
                    
        };
	
	
	if(animated){
		[UIView animateWithDuration:0.3 animations:SelectBlock completion:CompletionBlock];
	}
	else {
		SelectBlock();
		CompletionBlock(YES);
	}
	
}


#pragma mark -
#pragma mark PageScroller Data



- (void) reloadData; 
{
    NSInteger numPages = 1;  
	if ([self.dataSource respondsToSelector:@selector(numberOfPagesInScrollView:)]) {
		numPages = [self.dataSource numberOfPagesInScrollView:self];
	}
	
    NSInteger selectedIndex = _selectedPage?[_visiblePages indexOfObject:_selectedPage]:NSNotFound;
        
	// reset visible pages array
	[_visiblePages removeAllObjects];
	// remove all subviews from scrollView
    [[_scrollView subviews] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [obj removeFromSuperview];
    }]; 
     
	[self setNumberOfPages:numPages];
	
    // hide view components initially
    _pageHeaderView.alpha = 0.0;	
    _pageDeckTitleLabel.hidden = YES;
    _pageDeckSubtitleLabel.hidden = YES;
    
	if (_numberOfPages > 0) {
		
		// reload visible pages
		for (int index=0; index<_visibleIndexes.length; index++) {
			HGPageView *page = [self loadPageAtIndex:_visibleIndexes.location+index insertIntoVisibleIndex:index];
            [self addPageToScrollView:page atIndex:_visibleIndexes.location+index];
		}
		
		// this will load any additional views which become visible  
		[self updateVisiblePages];
		
        // set initial alpha values for all visible pages
        [_visiblePages enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [self setAlphaForPage : obj];		
        }];
		
        if (selectedIndex == NSNotFound) {
            // if no page is selected, select the first page
            _selectedPage = _visiblePages[0];
        }
        else{
            // refresh the page at the selected index (it might have changed after reloading the visible pages) 
            _selectedPage = _visiblePages[selectedIndex];
        }

        // update deck title and subtitle for selected page
        NSInteger index = [self indexForSelectedPage];
        if ([self.dataSource respondsToSelector:@selector(pageScrollView:titleForPageAtIndex:)]) {
            _pageDeckTitleLabel.text = [self.dataSource pageScrollView:self titleForPageAtIndex:index];
        }
        if ([self.dataSource respondsToSelector:@selector(pageScrollView:subtitleForPageAtIndex:)]) {
            _pageDeckSubtitleLabel.text = [self.dataSource pageScrollView:self subtitleForPageAtIndex:index];
        }	
        
        // show deck-mode title/subtitle
        _pageDeckTitleLabel.hidden = NO;
        _pageDeckSubtitleLabel.hidden = NO;

	}
    
    // reloading the data implicitely resets the viewMode to UIPageScrollViewModeDeck. 
    // here we restore the view mode in case this is not the first time reloadData is called (i.e. if there if a _selectedPage).   
    if (_selectedPage && self.viewMode==HGPageScrollViewModePage) { 
        self.viewMode = HGPageScrollViewModeDeck;
        [self setViewMode:HGPageScrollViewModePage animated:NO];
    }
}



- (HGPageView*) loadPageAtIndex : (NSInteger) index insertIntoVisibleIndex : (NSInteger) visibleIndex
{
	HGPageView *visiblePage = [self.dataSource pageScrollView:self viewForPageAtIndex:index];
    if (!visiblePage) return nil;
	if (visiblePage.reuseIdentifier) {
		NSMutableArray *reusables = _reusablePages[visiblePage.reuseIdentifier];
		if (!reusables) {
			reusables = [[NSMutableArray alloc] initWithCapacity : 4];
		}
		if (![reusables containsObject:visiblePage]) {
			[reusables addObject:visiblePage];
		}
		_reusablePages[visiblePage.reuseIdentifier] = reusables;
	}
	
	// add the page to the visible pages array
	[_visiblePages insertObject:visiblePage atIndex:visibleIndex];
		
    return visiblePage;
}


// add a page to the scroll view at a given index. No adjustments are made to existing pages offsets. 
- (void) addPageToScrollView : (HGPageView*) page atIndex : (NSInteger) index
{
    // inserting a page into the scroll view is in HGPageScrollViewModeDeck by definition (the scroll is the "deck")
    [self preparePage:page forMode:HGPageScrollViewModeDeck];
    
    CGRect frame = page.identityFrame;
    frame.origin.y = - _scrollView.frame.origin.y;
    frame.origin.x = -_scrollView.frame.origin.x + index * _scrollView.bounds.size.width;
    // store this frame for the backward animation
    page.identityFrame = frame; 
    
	// configure the page frame
    [self setFrameForPage : page atIndex:index];
    

    
    if (!HAS_IOS_7) {
		// add shadow (use shadowPath to improve rendering performance)
		page.layer.shadowColor = [[UIColor blackColor] CGColor];	
		page.layer.shadowOffset = CGSizeMake(8.0f, 12.0f);
		page.layer.shadowOpacity = 0.3f;
		page.layer.masksToBounds = NO;
		UIBezierPath *path = [UIBezierPath bezierPathWithRect:((ArticleView*)page).webView.frame];
		page.layer.shadowPath = path.CGPath;
	}
 
    // add the page to the scroller
	[_scrollView insertSubview:page atIndex:0];

}

// inserts a page to the scroll view at a given offset by pushing existing pages forward.
- (void) insertPageInScrollView : (HGPageView *) page atIndex : (NSInteger) index animated : (BOOL) animated
{
    //hide the new page before inserting it
    page.alpha = 0.0; 
    
    // add the new page at the correct offset
	[self addPageToScrollView:page atIndex:index]; 
    
    // shift pages at or after the new page offset forward
    [[_scrollView subviews] enumerateObjectsUsingBlock:^(id existingPage, NSUInteger idx, BOOL *stop) {

        if(existingPage != page && page.frame.origin.x <= ((UIView*)existingPage).frame.origin.x){
      
            if (animated) {
                [UIView animateWithDuration:0.4 animations:^(void) {
                    [self shiftPage : existingPage withOffset: _scrollView.frame.size.width];
                }];
            }
            else{
                [self shiftPage : existingPage withOffset: _scrollView.frame.size.width];
            }                
        }
    }];

    if (animated) {
        [UIView animateWithDuration:0.4 animations:^(void) {
            [self setAlphaForPage:page];
        }];
    }
    else{
        [self setAlphaForPage:page];
    }
 		
	

}



- (void) removePagesFromScrollView : (NSArray*) pages animated:(BOOL)animated
{
    CGFloat selectedPageOffset = NSNotFound;
    if ([pages containsObject:_selectedPage]) {
        selectedPageOffset = _selectedPage.frame.origin.x;
    }
    
    // remove the pages from the scrollView
	NSArray *pgs = [pages copy];
	[UIView animateWithDuration:0.3 animations:^{
		[pages enumerateObjectsUsingBlock:^(UIView *page, NSUInteger idx, BOOL *stop) {
			CGRect frm = page.frame;
			frm.origin.y = -CGRectGetHeight(frm);
			page.frame = frm;
		}];
	} completion:^(BOOL finished) {
		[pgs enumerateObjectsUsingBlock:^(UIView *page, NSUInteger idx, BOOL *stop) {
			[page removeFromSuperview];
		}];
	}];

         
    // shift the remaining pages in the scrollView
    [[_scrollView subviews] enumerateObjectsUsingBlock:^(id remainingPage, NSUInteger idx, BOOL *stop) {
        NSIndexSet *removedPages = [pages indexesOfObjectsPassingTest:^BOOL(id removedPage, NSUInteger idx, BOOL *stop) {
            return ((UIView*)removedPage).frame.origin.x < ((UIView*)remainingPage).frame.origin.x;
        }]; 
                
        if ([removedPages count] > 0) {
            
            if (animated) {
                [UIView animateWithDuration:0.4 animations:^(void) {
                    [self shiftPage : remainingPage withOffset: -([removedPages count]*_scrollView.frame.size.width)];
                }];
            }
            else{
                [self shiftPage : remainingPage withOffset: -([removedPages count]*_scrollView.frame.size.width)];
            }                
        }
        
    }];

    // update the selected page if it has been removed 
    if(selectedPageOffset != NSNotFound){
        NSInteger index = [[_scrollView subviews] indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            CGFloat delta = fabsf(((UIView*)obj).frame.origin.x - selectedPageOffset);
            return delta < 0.1;
        }];
        HGPageView *newSelectedPage=nil;
        if (index != NSNotFound) {
            // replace selected page with the new page which is in the same offset 
            newSelectedPage = [_scrollView subviews][index];
        }
        
        // This could happen when removing the last page
        if([self indexForVisiblePage:newSelectedPage] == NSNotFound) {
            // replace selected page with last visible page 
            newSelectedPage = [_visiblePages lastObject];
        }        
        NSInteger newSelectedPageIndex = [self indexForVisiblePage:newSelectedPage];
        if (newSelectedPage != _selectedPage) {
            [self updateScrolledPage:newSelectedPage index:newSelectedPageIndex];
        }
    }
}




- (void) setFrameForPage : (UIView*) page atIndex : (NSInteger) index;
{
    page.transform = CGAffineTransformIdentity;
    CGRect frm = page.frame;
	UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    if (![self.delegate shouldAutorotateToInterfaceOrientation:orientation]) {
        orientation = _lastOrientation;
    }
    if (!UIInterfaceOrientationIsPortrait(orientation) && !UIInterfaceOrientationIsLandscape(orientation)) {
        orientation = _lastOrientation;
    }
	NSUInteger statusBar = HAS_IOS_7 ? 0 : 20;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    {
        if (UIInterfaceOrientationIsLandscape(orientation)) {
            frm.size.width = SCREEN_HEIGHT;
            frm.size.height = 320 - 30 - statusBar;
        }
        else {
            frm.size.width = 320;
            frm.size.height = SCREEN_HEIGHT- statusBar - 44;
        }
    } else {
        if (UIInterfaceOrientationIsLandscape(orientation)) {
            frm.size.width = SCREEN_HEIGHT;
            frm.size.height = 748-44;
        }
        else {
            frm.size.width = 768;
            frm.size.height = SCREEN_HEIGHT - statusBar - 44;
        }
    }
    page.frame = frm;
    
    
    frm = ((HGPageView*)page).identityFrame;
    frm.origin.y = - _scrollView.frame.origin.y;
    frm.origin.x = -_scrollView.frame.origin.x + 
    index * _scrollView.bounds.size.width;
    // store this frame for the backward animation
    ((HGPageView*)page).identityFrame = frm; 
    
    if (self.viewMode == HGPageScrollViewModeDeck) {        
            
        page.transform = CGAffineTransformMakeScale(_miniScaleFactor, _miniScaleFactor);
        CGFloat contentOffset = index * _scrollView.frame.size.width;
        //CGFloat margin = (_scrollView.frame.size.width - page.frame.size.width) / 2; 
        CGRect frame = page.frame;
        frame.origin.x = contentOffset + _pageMargin;
        frame.origin.y = (self.frame.size.height - frame.size.height) * 0.5 - _scrollView.frame.origin.y;
        //frame.origin.y = 0.0;
        page.frame = frame;
        
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:page.bounds];
        page.layer.shadowPath = path.CGPath;
    }
}


- (void) shiftPage : (UIView*) page withOffset : (CGFloat) offset
{
    CGRect frame = page.frame;
    frame.origin.x += offset;
    page.frame = frame; 
    
    // also refresh the alpha of the shifted page
    [self setAlphaForPage : page];	
    
}



#pragma mark - insertion/deletion/reloading

- (void) prepareForDataUpdate : (HGPageScrollViewUpdateMethod) method withIndexSet : (NSIndexSet*) indexes
{
    // check if current mode allows data update
    /*if(self.viewMode == HGPageScrollViewModePage){
        // deleting pages is (currently) only supported in DECK mode.
        NSException *exception = [NSException exceptionWithName:kExceptionNameInvalidOperation reason:kExceptionReasonInvalidOperation userInfo:nil];
        [exception raise];
    }*/

    // check number of pages
    if ([self.dataSource respondsToSelector:@selector(numberOfPagesInScrollView:)]) {
		
        NSInteger newNumberOfPages = [self.dataSource numberOfPagesInScrollView:self];

        NSInteger expectedNumberOfPages;
        NSString *reason;
        switch (method) {
            case HGPageScrollViewUpdateMethodDelete:
                expectedNumberOfPages = _numberOfPages-[indexes count];
                reason = [NSString stringWithFormat:kExceptionReasonInvalidUpdate, newNumberOfPages, _numberOfPages, 0, [indexes count]];
                break;
            case HGPageScrollViewUpdateMethodInsert:
                expectedNumberOfPages = _numberOfPages+[indexes count];
                reason = [NSString stringWithFormat:kExceptionReasonInvalidUpdate, newNumberOfPages, _numberOfPages, [indexes count], 0];
                break;
            case HGPageScrollViewUpdateMethodReload:
                reason = [NSString stringWithFormat:kExceptionReasonInvalidUpdate, newNumberOfPages, _numberOfPages, 0, 0];
            default:
                expectedNumberOfPages = _numberOfPages;
                break;
        }
    
        if (newNumberOfPages != expectedNumberOfPages) {
            NSException *exception = [NSException exceptionWithName:kExceptionNameInvalidUpdate reason:reason userInfo:nil];
            [exception raise];
        }
	}
    
    // separate the indexes into 3 sets:
    self.indexesBeforeVisibleRange = nil;
    self.indexesBeforeVisibleRange = [indexes indexesPassingTest:^BOOL(NSUInteger idx, BOOL *stop) {
        return (idx < _visibleIndexes.location);
    }];
    self.indexesWithinVisibleRange = nil;
    self.indexesWithinVisibleRange = [indexes indexesPassingTest:^BOOL(NSUInteger idx, BOOL *stop) {
        return (idx >= _visibleIndexes.location && 
                (_visibleIndexes.length>0 ? idx < _visibleIndexes.location+_visibleIndexes.length : YES));
    }];
    
    self.indexesAfterVisibleRange = nil;
    self.indexesAfterVisibleRange = [indexes indexesPassingTest:^BOOL(NSUInteger idx, BOOL *stop) {
        return ((_visibleIndexes.length>0 ? idx >= _visibleIndexes.location+_visibleIndexes.length : NO));
    }];

}



- (void)insertPagesAtIndexes:(NSIndexSet *)indexes animated : (BOOL) animated;
{
    
    [self prepareForDataUpdate : HGPageScrollViewUpdateMethodInsert withIndexSet:indexes];
    
    // handle insertion of pages before the visible range. Shift pages forward.
    if([self.indexesBeforeVisibleRange count] > 0) {
        [self setNumberOfPages : _numberOfPages+[self.indexesBeforeVisibleRange count]];
        [[_scrollView subviews] enumerateObjectsUsingBlock:^(id page, NSUInteger idx, BOOL *stop) {
            [self shiftPage:page withOffset:[self.indexesBeforeVisibleRange count] * _scrollView.frame.size.width];
        }];
        
        _visibleIndexes.location += [self.indexesBeforeVisibleRange count]; 
        
        // update scrollView contentOffset
        CGPoint contentOffset = _scrollView.contentOffset;
        contentOffset.x += [self.indexesBeforeVisibleRange count] * _scrollView.frame.size.width;
        _scrollView.contentOffset = contentOffset;
        
        // refresh the page control
        [_pageSelector setCurrentPage:[self indexForSelectedPage]];

    }
    
    // handle insertion of pages within the visible range. 
    NSInteger selectedPageIndex = (_numberOfPages > 0)? [self indexForSelectedPage] : 0;
    [self setNumberOfPages:_numberOfPages +[self.indexesWithinVisibleRange count]];
    [self.indexesWithinVisibleRange enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
    
        HGPageView *page = [self loadPageAtIndex:idx insertIntoVisibleIndex: idx - _visibleIndexes.location];
        [self insertPageInScrollView:page atIndex:idx animated:animated]; 
        _visibleIndexes.length++; 
        if (_visibleIndexes.length > 3) {
            HGPageView *page = [_visiblePages lastObject];
            [page removeFromSuperview];
            [_visiblePages removeObject:page];
            _visibleIndexes.length--;
        }

    }];
    
    // update selected page if necessary
    if ([self.indexesWithinVisibleRange containsIndex:selectedPageIndex]) {
        [self updateScrolledPage:_visiblePages[(selectedPageIndex-_visibleIndexes.location)] index:selectedPageIndex];
    }
    
    // handle insertion of pages after the visible range
    if ([self.indexesAfterVisibleRange count] > 0) {
        [self setNumberOfPages:_numberOfPages +[self.indexesAfterVisibleRange count]];
    }
        

}


- (void)deletePagesAtIndexes:(NSIndexSet *)indexes animated:(BOOL)animated;
{

    [self prepareForDataUpdate : HGPageScrollViewUpdateMethodDelete withIndexSet:indexes];
    
    // handle deletion of indexes _before_ the visible range. 
    [self.indexesBeforeVisibleRange enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        // 'Removing' pages which are before the visible range is a special case because we don't really have an instance of these pages. 
        // Therefore, we create pseudo-pages to be 'removed' by removePagesFromScrollView:animated:. This method shifts all pages  
        // which follow the deleted ones backwards and adjusts the contentSize of the scrollView.

        //TODO: solve this limitation:
        // in order to shift pages backwards and trim the content size, the WIDTH of each deleted page needs to be known. 
        // We don't have an instance of the deleted pages and we cannot ask the data source to provide them because they've already been deleted. As a temp solution we take the default page width of 320. 
        // This assumption may be wrong if the data source uses anotehr page width or alternatively varying page widths.
		NSUInteger statusBar = HAS_IOS_7 ? 0 : 20;
        UIView *pseudoPage = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, SCREEN_HEIGHT - statusBar)];
        [self setFrameForPage:pseudoPage atIndex:idx];
        [_deletedPages addObject:pseudoPage];
        _visibleIndexes.location--;
    }];
    if ([_deletedPages count] > 0) {
        
        // removePagesFromScrollView:animated shifts all pages which follow the deleted pages backwards, and trims the scrollView contentSize respectively. As a result UIScrollView may adjust its contentOffset (if it is larger than the new contentSize). 
        // Here we store the oldOffset to make sure we adjust it by exactly the number of pages deleted. 
        CGFloat oldOffset = _scrollView.contentOffset.x;
        // set the new number of pages 
        [self setNumberOfPages:_numberOfPages - [_deletedPages count]];
        //_numberOfPages -= [_deletedPages count];
        
        [self removePagesFromScrollView:_deletedPages animated:NO]; //never animate removal of non-visible pages
        CGFloat newOffset = oldOffset - ([_deletedPages count] * _scrollView.frame.size.width);
        [_scrollView setContentOffset:CGPointMake(newOffset, _scrollView.contentOffset.y) animated:animated];

        for (HGPageView *page in _deletedPages) {
            [page prepareForDeletion];
        }
    }
    
        
    // handle deletion of pages _within_ and _after_ the visible range. 
    _numberOfFreshPages = 0;
    NSInteger numPagesAfterDeletion = _numberOfPages -= [self.indexesWithinVisibleRange count] + [self.indexesAfterVisibleRange count]; 
    [self.indexesWithinVisibleRange enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {

        // get the deleted page 
        [_deletedPages addObject: [self pageAtIndex:idx]];
        
        // load new pages to replace the deleted ones in the visible range 
        if (_visibleIndexes.location + _visibleIndexes.length <= numPagesAfterDeletion){
            // more pages are available after the visible range. Load a new page from the data source
            NSInteger newPageIndex = _visibleIndexes.location+_visibleIndexes.length - [_deletedPages count];
            HGPageView *page = [self loadPageAtIndex:newPageIndex insertIntoVisibleIndex:_visibleIndexes.length];            
            // insert the new page after the current visible pages. When the visible pages will be removed, 
            // in removePagesFromScrollView:animated:, these new page/s will enter the visible rectangle of the scrollView. 
            [self addPageToScrollView:page atIndex:newPageIndex+[self.indexesWithinVisibleRange count] ]; 
            _numberOfFreshPages++;
        }
        
    }];
    

    // update the visible range if necessary
    NSInteger deleteCount = [_deletedPages count];
    if(deleteCount>0 && _numberOfFreshPages < deleteCount){
        // Not enough fresh pages were loaded to fill in for the deleted pages in the visible range. 
        // This can only be a result of hitting the end of the page scroller. 
        // Adjust the visible range to show the end of the scroll (ideally the last 2 pages, or less). 
        NSInteger newLength = _visibleIndexes.length - deleteCount + _numberOfFreshPages;
        if (newLength >= 2) {
            _visibleIndexes.length = newLength;
        }
        else{
            if(_visibleIndexes.location==0){
                _visibleIndexes.length = newLength;
            }
            else{
                NSInteger delta = MIN(2-newLength, _visibleIndexes.location);
                _visibleIndexes.length = newLength + delta;
                _visibleIndexes.location -= delta; 
                
                //load 'delta' pages from before the visible range to replace deleted pages
                for (int i=0; i<delta; i++) {
                    HGPageView *page = [self loadPageAtIndex:_visibleIndexes.location+i insertIntoVisibleIndex:i];    
                    [self addPageToScrollView:page atIndex:_visibleIndexes.location+i ]; 
                }
            }

        }               
    }
    
    
    /* OLD
    // remove the pages marked for deletion from visiblePages 
    [_visiblePages removeObjectsInArray:_deletedPages];
    // ...and from the scrollView
    [self removePagesFromScrollView:_deletedPages animated:animated];

    //update number of pages.  
    [self setNumberOfPages:numPagesAfterDeletion];
    
    [_deletedPages removeAllObjects];
    
    [self scrollViewDidScroll:_scrollView];
    */
    
    
    
    // Temporarily update number of pages.
	_numberOfPages = numPagesAfterDeletion;
	// remove the pages marked for deletion from visiblePages 
	[_visiblePages removeObjectsInArray:_deletedPages];
	// ...and from the scrollView
	[self removePagesFromScrollView:_deletedPages animated:animated];
	// Actually update number of pages
	if (animated) {
		[UIView animateWithDuration:0.4 animations:^(void) {
			[self setNumberOfPages:numPagesAfterDeletion];
		}];
	} else {
		[self setNumberOfPages:numPagesAfterDeletion];
	}
    
    for (HGPageView *page in _deletedPages) {
        [page prepareForDeletion];
    }
    [_deletedPages removeAllObjects];
    
	// Update selected page.
	[self scrollViewDidScroll:_scrollView];
}

- (void)reloadPagesAtIndexes:(NSIndexSet *)indexes;
{
    [self prepareForDataUpdate : HGPageScrollViewUpdateMethodReload withIndexSet:indexes];

    // only reload pages within the visible range
    [self.indexesWithinVisibleRange enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        HGPageView *page = [self pageAtIndex:idx];
        [_visiblePages removeObject : page]; // remove from visiblePages
        [page removeFromSuperview];          // remove from scrollView
        
        page = [self loadPageAtIndex:idx insertIntoVisibleIndex: idx - _visibleIndexes.location];
        [self addPageToScrollView:page atIndex:idx];
    }];        
}


- (void) setNumberOfPages : (NSInteger) number 
{
    _numberOfPages = number; 
    CGSize newSize = CGSizeMake(_numberOfPages * _scrollView.bounds.size.width, 50);    
    /*if (newSize.width < _scrollView.contentSize.width) {
        [_scrollView setContentOffset:CGPointMake((_numberOfPages-1) * _scrollView.bounds.size.width, 0) animated:YES];
    }*/
    _scrollView.contentSize = newSize;
    _pageSelector.numberOfPages = _numberOfPages;      

}

#pragma mark -
#pragma mark UIScrollViewDelegate

- (void) scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if ([self.delegate respondsToSelector:@selector(pageScrollViewWillBeginDragging:)]) {
        [self.delegate pageScrollViewWillBeginDragging:self];
    }
}


- (void) scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if ([self.delegate respondsToSelector:@selector(pageScrollViewDidEndDragging:willDecelerate:)]) {
        [self.delegate pageScrollViewDidEndDragging:self willDecelerate:decelerate];
    }

    if (_isPendingScrolledPageUpdateNotification) {
        if ([self.delegate respondsToSelector:@selector(pageScrollView:didScrollToPage:atIndex:)]) {
            NSInteger selectedIndex = [_visiblePages indexOfObject:_selectedPage];
            [self.delegate pageScrollView:self didScrollToPage:_selectedPage atIndex:selectedIndex];
        }
        _isPendingScrolledPageUpdateNotification = NO;
    }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView
{
    if ([self.delegate respondsToSelector:@selector(pageScrollViewWillBeginDecelerating:)]) {
        [self.delegate pageScrollViewWillBeginDecelerating:self];
    }
  
}


- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if ([self.delegate respondsToSelector:@selector(pageScrollViewDidEndDecelerating:)]) {
        [self.delegate pageScrollViewDidEndDecelerating:self];
    }
}


- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (self.isRotating) {
        return;
    }
	// update the visible pages
	[self updateVisiblePages];
	
	// adjust alpha for all visible pages
	[_visiblePages enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		[self setAlphaForPage : obj];		
	}];
	
	
	CGFloat delta = scrollView.contentOffset.x - _selectedPage.frame.origin.x;
	BOOL toggleNextItem = (fabs(delta) > scrollView.frame.size.width / 2);
	if (toggleNextItem && [_visiblePages count] > 1) {
		
		NSInteger selectedIndex = [_visiblePages indexOfObject:_selectedPage];
		BOOL neighborExists = ((delta < 0 && selectedIndex > 0) || (delta > 0 && selectedIndex < [_visiblePages count]-1));
		
		if (neighborExists) {
			
			NSInteger neighborPageVisibleIndex = [_visiblePages indexOfObject:_selectedPage] + (delta > 0? 1:-1);
			HGPageView *neighborPage = _visiblePages[neighborPageVisibleIndex];
			NSInteger neighborIndex = _visibleIndexes.location + neighborPageVisibleIndex;

			[self updateScrolledPage:neighborPage index:neighborIndex];
			
		}
		
	}

}


- (void) updateScrolledPage : (HGPageView*) page index : (NSInteger) index
{
    if (!page) {
         _pageDeckTitleLabel.text = @"";
        _pageDeckSubtitleLabel.text = @"";
        _selectedPage = nil;
    }
    else{
        // notify delegate
        if ([self.delegate respondsToSelector:@selector(pageScrollView:willScrollToPage:atIndex:)]) {
            [self.delegate pageScrollView:self willScrollToPage:page atIndex:index];
        }
        
        // update title and subtitle
        if ([self.dataSource respondsToSelector:@selector(pageScrollView:titleForPageAtIndex:)]) {
            _pageDeckTitleLabel.text = [self.dataSource pageScrollView:self titleForPageAtIndex:index];
        }
        if ([self.dataSource respondsToSelector:@selector(pageScrollView:subtitleForPageAtIndex:)]) {
            _pageDeckSubtitleLabel.text = [self.dataSource pageScrollView:self subtitleForPageAtIndex:index];
        }
        
        // set the page selector (page control)
        [_pageSelector setCurrentPage:index];

        // set selected page
        _selectedPage = page;
        
        if (_scrollView.dragging) {
            _isPendingScrolledPageUpdateNotification = YES;
        }
        else{
            // notify delegate again
            if ([self.delegate respondsToSelector:@selector(pageScrollView:didScrollToPage:atIndex:)]) {
                [self.delegate pageScrollView:self didScrollToPage:page atIndex:index];
            }
            _isPendingScrolledPageUpdateNotification = NO;
        }	       
    }

}



- (void) updateVisiblePages
{
	CGFloat pageWidth = _scrollView.frame.size.width;

	//get x origin of left- and right-most pages in _scrollView's superview coordinate space (i.e. self)  
	CGFloat leftViewOriginX = _scrollView.frame.origin.x - _scrollView.contentOffset.x + (_visibleIndexes.location * pageWidth);
	CGFloat rightViewOriginX = _scrollView.frame.origin.x - _scrollView.contentOffset.x + (_visibleIndexes.location+_visibleIndexes.length-1) * pageWidth;
	
	if (leftViewOriginX > 0) {
		//new page is entering the visible range from the left
		if (_visibleIndexes.location > 0) { //is it not the first page?
			_visibleIndexes.length += 1;
			_visibleIndexes.location -= 1;
			HGPageView *page = [self loadPageAtIndex:_visibleIndexes.location insertIntoVisibleIndex:0];
            // add the page to the scroll view (to make it actually visible)
            [self addPageToScrollView:page atIndex:_visibleIndexes.location ];

		}
	}
	else if(leftViewOriginX < -pageWidth){
		//left page is exiting the visible range
        if ([_visiblePages count] > 0) {
            UIView *page = _visiblePages[0];
            [_visiblePages removeObject:page];
            [page removeFromSuperview]; //remove from the scroll view
            _visibleIndexes.location += 1;
            _visibleIndexes.length -= 1;
        }
	}
	if (rightViewOriginX > self.frame.size.width) {
		//right page is exiting the visible range
		UIView *page = [_visiblePages lastObject];
        if (page != _selectedPage) {
            [_visiblePages removeObject:page];
            [page removeFromSuperview]; //remove from the scroll view
            _visibleIndexes.length -= 1;
        }
	}
	else if(rightViewOriginX + pageWidth < self.frame.size.width){
		//new page is entering the visible range from the right
		if (_visibleIndexes.location + _visibleIndexes.length < _numberOfPages) { //is is not the last page?
			_visibleIndexes.length += 1;
            NSInteger index = _visibleIndexes.location+_visibleIndexes.length-1;
			HGPageView *page = [self loadPageAtIndex:index insertIntoVisibleIndex:_visibleIndexes.length-1];
            [self addPageToScrollView:page atIndex:index];

		}
	}
}


- (void) setAlphaForPage : (UIView*) page
{
    if (self.viewMode == HGPageScrollViewModePage) return;
	CGFloat delta = _pageMargin + _scrollView.contentOffset.x - page.frame.origin.x;
	CGFloat step = self.frame.size.width;
	CGFloat alpha = 1.0 - fabs(delta/step);
	if(alpha > 0.95) alpha = 1.0;
    page.alpha = alpha;
}



- (void) initHeaderForPageAtIndex : (NSInteger) index
{
	if ([self.dataSource respondsToSelector:@selector(pageScrollView:titleForPageAtIndex:)]) {
		UILabel *titleLabel = (UILabel*)[_pageHeaderView viewWithTag:1];
		titleLabel.text = [self.dataSource pageScrollView:self titleForPageAtIndex:index];
	}
	
	if ([self.dataSource respondsToSelector:@selector(pageScrollView:subtitleForPageAtIndex:)]) {		
		UILabel *subtitleLabel = (UILabel*)[_pageHeaderView viewWithTag:2];
		subtitleLabel.text = [self.dataSource pageScrollView:self subtitleForPageAtIndex:index];
	}
	
}


- (void) initDeckTitlesForPageAtIndex : (NSInteger) index;
{
	if ([self.dataSource respondsToSelector:@selector(pageScrollView:titleForPageAtIndex:)]) {
		_pageDeckTitleLabel.text = [self.dataSource pageScrollView:self titleForPageAtIndex:index];
	}

	if ([self.dataSource respondsToSelector:@selector(pageScrollView:subtitleForPageAtIndex:)]) {
		_pageDeckSubtitleLabel.text = [self.dataSource pageScrollView:self subtitleForPageAtIndex:index];
	}
	
}


- (HGPageView *)dequeueReusablePageWithIdentifier:(NSString *)identifier;  // Used by the delegate to acquire an already allocated page, instead of allocating a new one
{
	HGPageView *reusablePage = nil;
	NSArray *reusables = _reusablePages[identifier];
	if (reusables){
		NSEnumerator *enumerator = [reusables objectEnumerator];
		while ((reusablePage = [enumerator nextObject])) {
			if(![_visiblePages containsObject:reusablePage]){
				[reusablePage prepareForReuse];
				break;
			}
		}
	}
	return reusablePage;
}


#pragma mark -
#pragma mark Handling Touches


- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
	if ([gestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]] && self.viewMode == HGPageScrollViewModeDeck) {
		for (UIView *subview in self.subviews) {
			if ([subview isKindOfClass:[HGTouchView class]] && CGRectContainsPoint(subview.frame, [touch locationInView:self])) {
				return YES;
			}
		}
		return NO;
	}
	if (self.viewMode == HGPageScrollViewModeDeck && !_scrollView.decelerating && !_scrollView.dragging) {
		return YES;	
        if ([_selectedPage hitTest:[touch locationInView:_selectedPage] withEvent:nil]) {
            [self handleTapGestureFrom:nil];
        }
	}
	return NO;	
}

- (void) handleSwipeGesture:(UISwipeGestureRecognizer *)recognizer {
	if (recognizer.state == UIGestureRecognizerStateEnded) {
		[self deleteButtonPressed:nil];
	}
}


- (void)handleTapGestureFrom:(UITapGestureRecognizer *)recognizer 
{
    if(!_selectedPage)
        return;
    
	NSInteger selectedIndex = [self indexForSelectedPage];
	
	[self selectPageAtIndex:selectedIndex animated:YES];
		
}


#pragma mark -
#pragma mark Actions


- (void) didChangePageValue : (id) sender;
{
	NSInteger selectedIndex = [self indexForSelectedPage];
	if(_pageSelector.currentPage != selectedIndex){
		//set pageScroller
		selectedIndex = _pageSelector.currentPage;
		//_userInitiatedScroll = NO;		
		[self scrollToPageAtIndex:selectedIndex animated:YES];			
	}
}



@end
