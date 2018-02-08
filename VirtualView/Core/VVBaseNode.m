//
//  VVBaseNode.m
//  VirtualView
//
//  Copyright (c) 2017-2018 Alibaba. All rights reserved.
//

#import "VVBaseNode.h"

@interface VVBaseNode () {
    NSMutableArray *_subNodes;
    BOOL needsLayout;
    BOOL updatingNeedsLayout; // to avoid infinite loop
}

@end

@implementation VVBaseNode

@synthesize subNodes = _subNodes;

- (id)init{
    self = [super init];
    if (self) {
        _subNodes = [[NSMutableArray alloc] init];
        _backgroundColor = [UIColor clearColor];
        _layoutGravity = VVGravityLeft | VVGravityTop;
        _gravity = VVGravityLeft | VVGravityTop;
        _visibility = VVVisibilityVisible;
        _layoutDirection = VVDirectionLeft | VVDirectionTop;
        _autoDimDirection = VVAutoDimDirectionNone;
        [self setNeedsLayoutNotRecursively];
    }
    return self;
}

#pragma mark Properties

- (CGSize)nodeSize
{
    return CGSizeMake(self.nodeWidth, self.nodeHeight);
}

- (CGSize)contentSize
{
    return CGSizeMake(self.nodeWidth - _paddingLeft - _paddingRight,
                      self.nodeHeight - _paddingTop - _paddingBottom);
}

- (CGSize)containerSize
{
    return CGSizeMake(self.nodeWidth + _marginLeft + _marginRight,
                      self.nodeHeight + _marginTop + _marginBottom);
}

- (void)setRootCocoaView:(UIView *)rootCocoaView
{
    _rootCocoaView = rootCocoaView;
    for (VVBaseNode *subNode in self.subNodes) {
        subNode.rootCocoaView = rootCocoaView;
    }
}

- (void)setRootCanvasLayer:(CALayer *)rootCanvasLayer
{
    _rootCanvasLayer = rootCanvasLayer;
    for (VVBaseNode *subNode in self.subNodes) {
        subNode.rootCanvasLayer = rootCanvasLayer;
    }
}

- (NSMutableDictionary *)expressionSetters
{
    if (!_expressionSetters) {
        _expressionSetters = [NSMutableDictionary new];
    }
    return _expressionSetters;
}

#pragma mark ClickEvents

- (BOOL)isClickable
{
    return (self.flag & VVFlagClickable) > 0;
}

- (BOOL)isLongClickable
{
    return (self.flag & VVFlagLongClickable) > 0;
}

- (BOOL)supportExposure
{
    return (self.flag & VVFlagExposure) > 0;
}

- (VVBaseNode *)hitTest:(CGPoint)point
{
    if (self.visibility == VVVisibilityVisible
        && CGRectContainsPoint(self.nodeFrame, point)) {
        if (self.subNodes.count > 0) {
            for (VVBaseNode* subNode in [self.subNodes reverseObjectEnumerator]) {
                VVBaseNode *hitNode = [subNode hitTest:point];
                if (hitNode) {
                    return hitNode;
                }
            }
        }
        if ([self isClickable] || [self isLongClickable]) {
            return self;
        }
    }
    return nil;
}

#pragma mark NodeTree

- (VVBaseNode *)nodeWithID:(NSInteger)nodeID
{
    if (self.nodeID == nodeID) {
        return self;
    }
    for (VVBaseNode *subNode in self.subNodes) {
        VVBaseNode *targetNode = [subNode nodeWithID:nodeID];
        if (targetNode) {
            return targetNode;
        }
    }
    return nil;
}

- (void)addSubNode:(VVBaseNode *)node
{
    if (nil != node) {
        [_subNodes addObject:node];
        node->_superNode = self;
    }
}

- (void)removeSubNode:(VVBaseNode*)node
{
    if (nil != node && [_subNodes containsObject:node]) {
        [_subNodes removeObject:node];
        node->_superNode = nil;
    }
}

- (void)removeFromSuperNode
{
    if (nil != self.superNode) {
        [self.superNode removeSubNode:self];
    }
}

#pragma mark Layout

- (void)setupObserver
{
    VVNeedsLayoutObserve(layoutWidth);
    VVNeedsLayoutObserve(layoutHeight);
    VVNeedsLayoutObserve(autoDimX);
    VVNeedsLayoutObserve(autoDimY);
    VVNeedsLayoutObserve(autoDimDirection);
    VVSubNodeNeedsLayoutObserve(paddingTop);
    VVSubNodeNeedsLayoutObserve(paddingLeft);
    VVSubNodeNeedsLayoutObserve(paddingRight);
    VVSubNodeNeedsLayoutObserve(paddingBottom);
    VVSuperNodeNeedsLayoutObserve(marginTop);
    VVSuperNodeNeedsLayoutObserve(marginLeft);
    VVSuperNodeNeedsLayoutObserve(marginRight);
    VVSuperNodeNeedsLayoutObserve(marginBottom);
    VVSuperNodeNeedsLayoutObserve(layoutRatio);
    __weak VVBaseNode *weakSelf = self;
    [self vv_addObserverForKeyPath:VVKeyPath(gravity) block:^(id _Nonnull value) {
        __strong VVBaseNode *strongSelf = weakSelf;
        [strongSelf setNeedsLayoutNotRecursively];
    }];
    [self vv_addObserverForKeyPath:VVKeyPath(layoutGravity) block:^(id _Nonnull value) {
        __strong VVBaseNode *strongSuperNode = weakSelf.superNode;
        [strongSuperNode setNeedsLayoutNotRecursively];
    }];
    [self vv_addObserverForKeyPath:VVKeyPath(layoutDirection) block:^(id _Nonnull value) {
        __strong VVBaseNode *strongSuperNode = weakSelf.superNode;
        [strongSuperNode setNeedsLayoutNotRecursively];
    }];
}

- (BOOL)needsLayoutIfSubNodeLayout
{
    return self.layoutWidth == VV_WRAP_CONTENT || self.layoutHeight == VV_WRAP_CONTENT;
}

- (BOOL)needsLayoutIfSuperNodeLayout
{
    return self.layoutWidth == VV_MATCH_PARENT || self.layoutHeight == VV_MATCH_PARENT;
}

- (void)setSubNodeNeedsLayout
{
    updatingNeedsLayout = YES;
    for (VVBaseNode *subNode in self.subNodes) {
        if ([subNode needsLayoutIfSuperNodeLayout]) {
            [subNode setNeedsLayout];
        }
    }
    updatingNeedsLayout = NO;
}

- (void)setSuperNodeNeedsLayout
{
    updatingNeedsLayout = YES;
    if (self.superNode && [self.superNode needsLayoutIfSubNodeLayout]) {
        [self.superNode setNeedsLayout];
    }
    updatingNeedsLayout = NO;
}

- (void)setNeedsLayout
{
    if (updatingNeedsLayout) {
        return;
    }
    [self setNeedsLayoutNotRecursively];
    [self setSuperNodeNeedsLayout];
    [self setSubNodeNeedsLayout];
}

- (void)setNeedsLayoutNotRecursively
{
    needsLayout = YES;
    _nodeWidth = -1;
    _nodeHeight = -1;
}

- (void)setNeedsLayoutRecursively
{
    [self setNeedsLayoutNotRecursively];
    for (VVBaseNode *subNode in self.subNodes) {
        [subNode setNeedsLayoutRecursively];
    }
}

- (void)layoutIfNeeded
{
    if (needsLayout) {
        [self layoutSubNodes];
    }
}

- (void)layoutSubviews
{
    [self layoutSubNodes];
}

- (void)layoutSubNodes
{
    // override me
    needsLayout = NO;
}

- (void)applyAutoDim
{
    if (self.autoDimX > 0 && self.autoDimY > 0) {
        if (self.autoDimDirection == VVAutoDimDirectionX) {
            self.nodeHeight = self.nodeWidth / self.autoDimX * self.autoDimY;
        } else if (self.autoDimDirection == VVAutoDimDirectionY) {
            self.nodeWidth = self.nodeHeight / self.autoDimY * self.autoDimX;
        }
    }
}

- (CGSize)calculateLayoutSize:(CGSize)maxSize
{
    return [self calculateSize:maxSize];
}

- (CGSize)calculateSize:(CGSize)maxSize
{
    if (self.nodeWidth < 0 || self.nodeHeight < 0) {
        self.nodeWidth = 0;
        if (self.layoutWidth == VV_MATCH_PARENT) {
            self.nodeWidth = maxSize.width - self.marginLeft - self.marginRight;
        } else if (self.layoutWidth > 0) {
            self.nodeWidth = self.layoutWidth;
        }
        
        self.nodeHeight = 0;
        if (self.layoutHeight == VV_MATCH_PARENT) {
            self.nodeHeight = maxSize.height - self.marginTop - self.marginBottom;
        } else if (self.layoutHeight > 0) {
            self.nodeHeight = self.layoutHeight;
        }
        
        [self applyAutoDim];
    }
    return CGSizeMake(self.nodeWidth, self.nodeHeight);
}

#pragma mark Update

- (void)changeCocoaViewSuperView{
    if (self.cocoaView.superview && self.visibility==VVVisibilityGone) {
        [self.cocoaView removeFromSuperview];
    }else if(self.cocoaView.superview==nil && self.visibility!=VVVisibilityGone){
        [self.rootCocoaView addSubview:self.cocoaView];
    }
}

- (BOOL)setIntValue:(int)value forKey:(int)key
{
    BOOL ret = YES;
    switch (key) {
        case STR_ID_layoutWidth:
            _layoutWidth = value;
            break;
        case STR_ID_layoutHeight:
            _layoutHeight = value;
            break;
        case STR_ID_paddingLeft:
            _paddingLeft = value;
            break;
        case STR_ID_paddingTop:
            _paddingTop = value;
            break;
        case STR_ID_paddingRight:
            _paddingRight = value;
            break;
        case STR_ID_paddingBottom:
            _paddingBottom = value;
            break;
        case STR_ID_layoutMarginLeft:
            _marginLeft = value;
            break;
        case STR_ID_layoutMarginTop:
            _marginTop = value;
            break;
        case STR_ID_layoutMarginRight:
            _marginRight = value;
            break;
        case STR_ID_layoutMarginBottom:
            _marginBottom = value;
            break;
        case STR_ID_layoutGravity:
            _layoutGravity = value;
            break;
        case STR_ID_id:
            _nodeID = value;
            break;
        case STR_ID_background:
            self.backgroundColor = [UIColor vv_colorWithARGB:(NSUInteger)value];
            break;
            
        case STR_ID_gravity:
            self.gravity = value;
            break;
            
        case STR_ID_flag:
            _flag = value;
            break;
            
        case STR_ID_uuid:
            #ifdef VV_DEBUG
                NSLog(@"STR_ID_uuid:%d",value);
            #endif
            break;
            
        case STR_ID_autoDimDirection:
            #ifdef VV_DEBUG
                NSLog(@"STR_ID_autoDimDirection:%d",value);
            #endif
            _autoDimDirection = value;
            break;
            
        case STR_ID_autoDimX:
            #ifdef VV_DEBUG
                NSLog(@"STR_ID_autoDimX:%d",value);
            #endif
            _autoDimX = value;
            break;
            
        case STR_ID_autoDimY:
            #ifdef VV_DEBUG
                NSLog(@"STR_ID_autoDimY:%d",value);
            #endif
            _autoDimY = value;
            break;
        case STR_ID_layoutRatio:
            self.layoutRatio = value;
            break;
        case STR_ID_visibility:
            self.visibility = value;
            switch (self.visibility) {
                case VVVisibilityInvisible:
                    self.cocoaView.hidden = YES;
                    break;
                case VVVisibilityVisible:
                    self.cocoaView.hidden = NO;
                    break;
                case VVVisibilityGone:
                    self.cocoaView.hidden = YES;
                    break;
            }
            [self changeCocoaViewSuperView];
            break;
        case STR_ID_layoutDirection:
            self.layoutDirection = value;
        default:
            ret = false;
    }

    return ret;
}

- (BOOL)setFloatValue:(float)value forKey:(int)key
{
    BOOL ret = YES;
    switch (key) {

        case STR_ID_layoutWidth:
            _layoutWidth = value;
            break;
        case STR_ID_layoutHeight:
            _layoutHeight = value;
            break;
        case STR_ID_paddingLeft:
            _paddingLeft = value;
            break;
        case STR_ID_paddingTop:
            _paddingTop = value;
            break;
        case STR_ID_paddingRight:
            _paddingRight = value;
            break;
        case STR_ID_paddingBottom:
            _paddingBottom = value;
            break;
        case STR_ID_layoutMarginLeft:
            _marginLeft = value;
            break;
        case STR_ID_layoutMarginTop:
            _marginTop = value;
            break;
        case STR_ID_layoutMarginRight:
            _marginRight = value;
            break;
        case STR_ID_layoutMarginBottom:
            _marginBottom = value;
            break;
        case STR_ID_layoutGravity:
            _layoutGravity = value;
            break;
        case STR_ID_id:
            _nodeID = value;
            break;
        case STR_ID_background:
            self.backgroundColor = [UIColor vv_colorWithARGB:(int)value];
            break;
            
        case STR_ID_gravity:
            self.gravity = value;
            break;
            
        case STR_ID_flag:
            _flag = value;
            break;
            
        case STR_ID_uuid:
            #ifdef VV_DEBUG
                NSLog(@"STR_ID_uuid:%f",value);
            #endif
            break;
            
        case STR_ID_autoDimDirection:
            #ifdef VV_DEBUG
                NSLog(@"STR_ID_autoDimDirection:%f",value);
            #endif
            _autoDimDirection = value;
            break;
            
        case STR_ID_autoDimX:
            #ifdef VV_DEBUG
                NSLog(@"STR_ID_autoDimX:%f",value);
            #endif
            _autoDimX = value;
            break;
            
        case STR_ID_autoDimY:
            #ifdef VV_DEBUG
                NSLog(@"STR_ID_autoDimY:%f",value);
            #endif
            _autoDimY = value;
            break;
        case STR_ID_layoutRatio:
            self.layoutRatio = value;
            break;
        case STR_ID_visibility:
            self.visibility = value;
            switch (self.visibility) {
                case VVVisibilityInvisible:
                    self.cocoaView.hidden = YES;
                    break;
                case VVVisibilityVisible:
                    self.cocoaView.hidden = NO;
                    break;
                case VVVisibilityGone:
                    //
                    break;
            }
            [self changeCocoaViewSuperView];
            break;
        default:
            ret = false;
            break;
    }
    
    return ret;
}

- (BOOL)setStringValue:(NSString *)value forKey:(int)key
{
    BOOL ret = YES;
    switch (key) {

        case STR_ID_data:
            break;

        case STR_ID_dataTag:
            self.dataTag = value;
            break;

        case STR_ID_action:
            self.action = value;
            break;

        case STR_ID_class:
            self.className = value;
            break;

        case STR_ID_background:
            self.backgroundColor = [UIColor vv_colorWithString:value];
            break;
        default:
            ret = NO;
    }
    return ret;
}

- (BOOL)setStringDataValue:(NSString*)value forKey:(int)key
{
    BOOL ret = true;
    switch (key) {
        case STR_ID_onClick:
            break;
            
        case STR_ID_onBeforeDataLoad:
            break;
            
        case STR_ID_onAfterDataLoad:
            break;
            
        case STR_ID_onSetData:
            break;
            
        default:
            ret = false;
    }
    
    return ret;
}

- (void)setDataObj:(NSObject *)obj forKey:(int)key
{
    // override me
}

- (void)reset
{
    // override me
}

- (void)didUpdated
{
    // override me
}

@end
