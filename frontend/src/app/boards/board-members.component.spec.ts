import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';

import { AuthService } from '../auth/auth.service';
import { Board } from '../models/board';
import { BoardMembersComponent } from './board-members.component';

describe('BoardMembersComponent', () => {
  let http: HttpTestingController;
  const board: Board = { id: 7, name: 'Sprint', owner: 'alice' };

  /** Signs in as `username` without keycloak-js. */
  function setup(username: string, admin = false) {
    TestBed.configureTestingModule({
      imports: [BoardMembersComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: { username: signal(username), isAdmin: signal(admin) } }
      ]
    });
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(BoardMembersComponent);
    fixture.componentRef.setInput('board', board);
    fixture.detectChanges();
    http.expectOne('/api/boards/7/members').flush([{ id: 1, boardId: 7, username: 'bob' }]);
    fixture.detectChanges();
    const el: HTMLElement = fixture.nativeElement;
    return { fixture, component: fixture.componentInstance, el };
  }

  afterEach(() => http.verify());

  it('F2/F3 - shows members to a member, without add/remove controls', () => {
    const { el, component } = setup('bob');
    expect(el.textContent).toContain('bob');
    expect(el.textContent).toContain('Owner: alice');
    expect(component.canManage()).toBeFalse();
    expect(el.querySelector('form.add-member')).toBeNull();
    expect(el.querySelector('button.danger')).toBeNull();
  });

  it('F3 - gives the owner the add and remove controls', () => {
    const { el } = setup('alice');
    expect(el.querySelector('form.add-member')).not.toBeNull();
    expect(el.querySelector('button.danger')?.textContent).toContain('Remove');
  });

  it('F3 - gives an admin the controls on someone else\'s board', () => {
    const { el } = setup('carol', true);
    expect(el.querySelector('form.add-member')).not.toBeNull();
  });

  it('POSTs the new member and inserts it in order', () => {
    const { component } = setup('alice');
    component.newUsername = ' Anna ';
    component.addMember();

    const post = http.expectOne('/api/boards/7/members');
    expect(post.request.method).toBe('POST');
    expect(post.request.body).toEqual({ username: 'Anna' });
    post.flush({ id: 2, boardId: 7, username: 'anna' });

    expect(component.members().map(m => m.username)).toEqual(['anna', 'bob']);
    expect(component.newUsername).toBe('');
  });

  it('F4 - surfaces the server\'s 400 message (duplicate / owner)', () => {
    const { fixture, component, el } = setup('alice');
    component.newUsername = 'bob';
    component.addMember();
    http.expectOne('/api/boards/7/members').flush(
      { error: 'bob is already a member of this board' }, { status: 400, statusText: 'Bad Request' });
    fixture.detectChanges();

    expect(component.error()).toBe('Could not add "bob": bob is already a member of this board');
    expect(el.querySelector('.error')?.textContent).toContain('already a member');
  });

  it('F4 - explains a 403 in plain words', () => {
    const { component } = setup('alice');
    spyOn(window, 'confirm').and.returnValue(true);
    component.removeMember({ boardId: 7, username: 'bob' });
    http.expectOne('/api/boards/7/members/bob').flush({ error: 'x' }, { status: 403, statusText: 'Forbidden' });

    expect(component.error()).toBe('Could not remove "bob": only the board owner can manage its members');
    expect(component.members().length).toBe(1);
  });

  it('DELETEs a member after confirmation', () => {
    const { component } = setup('alice');
    spyOn(window, 'confirm').and.returnValue(true);
    component.removeMember({ boardId: 7, username: 'bob' });

    const del = http.expectOne('/api/boards/7/members/bob');
    expect(del.request.method).toBe('DELETE');
    del.flush(null);
    expect(component.members()).toEqual([]);
  });
});
